import { etagMatches, parseRange } from "./range";
import { verifyToken } from "./sign";

export interface Env {
  BUCKET: R2Bucket;
  MEDIA_EDGE_SECRET: string;
  MAX_TTL_SECONDS?: string;
  EDGE_CACHE_TTL_SECONDS?: string;
  /** Optional bindings, all absent by default (see wrangler.toml). */
  TOKEN_LIMITER?: RateLimit; // per token
  IP_LIMITER?: RateLimit; // per client IP
  METRICS?: AnalyticsEngineDataset; // usage counters, off by default
}

/** Cache granularity. R2 is read and cached in aligned chunks of this size. */
export const CHUNK_SIZE = 4 * 1024 * 1024;
/**
 * Most bytes one response carries. A shorter 206 than asked is legal (Content-Range
 * says what is sent) and the player simply asks again. It bounds Cache API and R2
 * calls per invocation (Workers Free allows 50 subrequests, Paid 1000).
 *
 * The client's chunk size comes from download-url (`chunkBytes`, a multiple of
 * CHUNK_SIZE, at most 32 MiB). Chunk-aligned client requests therefore map onto whole
 * Worker chunks, and one client chunk is one request. 9 chunks (36 MiB) leaves room for
 * one misaligned 32 MiB request (it touches 9 aligned chunks) to still be answered whole.
 */
export const MAX_SPAN = 9 * CHUNK_SIZE; // 36 MiB

const CACHE_ORIGIN = "https://media-edge.invalid"; // synthetic: the cache key never leaves the colo

type Meta = { size: number; etag: string; lastModified: string; contentType: string };

const text = (status: number, code: string, extra: HeadersInit = {}) =>
  new Response(JSON.stringify({ error: code }), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...extra },
  });

const tooMany = () => text(429, "rate_limited", { "Retry-After": "15" });

/** `/v1/<key>` to the decoded object key, or null. */
export function objectKeyFromPath(pathname: string): string | null {
  if (!pathname.startsWith("/v1/")) return null;
  const parts = pathname.slice(4).split("/");
  try {
    const decoded = parts.map(decodeURIComponent);
    const key = decoded.join("/");
    if (!key || key.length > 1024) return null;
    if (key.split("/").some((p) => p === "" || p === "." || p === "..")) return null;
    if (/[\u0000-\u001f\u007f]/.test(key)) return null;
    return key;
  } catch {
    return null;
  }
}

const num = (v: string | undefined, d: number) => (v && Number.isFinite(Number(v)) && Number(v) > 0 ? Number(v) : d);

export interface Deps {
  cache: Cache;
  now: () => number; // ms
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handle(request, env, ctx, { cache: (caches as unknown as { default: Cache }).default, now: Date.now });
  },
} satisfies ExportedHandler<Env>;

export async function handle(request: Request, env: Env, ctx: ExecutionContext, deps: Deps): Promise<Response> {
  const res = await route(request, env, ctx, deps);
  try {
    // One non-blocking data point per request: status, cache result, bytes promised.
    // Never the URL, key or token. `bytes` is Content-Length, not bytes actually
    // delivered (a player that disconnects early is still counted in full).
    env.METRICS?.writeDataPoint({
      indexes: ["media-edge"],
      blobs: [String(res.status), res.headers.get("X-Edge-Cache") ?? "NA", request.method],
      doubles: [Number(res.headers.get("Content-Length") ?? 0)],
    });
  } catch {
    // metrics must never affect delivery
  }
  return res;
}

async function route(request: Request, env: Env, ctx: ExecutionContext, deps: Deps): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return text(405, "method_not_allowed", { Allow: "GET, HEAD" });
  }
  const url = new URL(request.url);
  const objectKey = objectKeyFromPath(url.pathname);
  if (!objectKey) return text(404, "not_found");
  if (!env.MEDIA_EDGE_SECRET) return text(500, "misconfigured");

  const nowSec = Math.floor(deps.now() / 1000);
  const verdict = await verifyToken(
    env.MEDIA_EDGE_SECRET,
    objectKey,
    url.searchParams.get("exp"),
    url.searchParams.get("sig"),
    nowSec,
    num(env.MAX_TTL_SECONDS, 90000),
  );
  if (verdict === "malformed") return text(400, "malformed_token");
  if (verdict !== "ok") return text(403, verdict === "expired" ? "expired" : "forbidden");

  // Limits run after the signature check, so forged traffic cannot burn a real viewer's
  // allowance, and before any R2 or cache work. Counts are per data centre and approximate.
  const sigKey = url.searchParams.get("sig")!;
  if (env.TOKEN_LIMITER && !(await env.TOKEN_LIMITER.limit({ key: sigKey })).success) return tooMany();
  const ip = request.headers.get("CF-Connecting-IP");
  if (env.IP_LIMITER && ip && !(await env.IP_LIMITER.limit({ key: ip })).success) return tooMany();

  const exp = Number(url.searchParams.get("exp"));
  const ttl = num(env.EDGE_CACHE_TTL_SECONDS, 21600);
  const meta = await loadMeta(env, ctx, deps, objectKey, ttl);
  if (!meta) return text(404, "not_found");

  const clientMaxAge = Math.max(0, Math.min(3600, exp - nowSec));
  const base: Record<string, string> = {
    "Accept-Ranges": "bytes",
    ETag: meta.etag,
    "Last-Modified": meta.lastModified,
    "Content-Type": meta.contentType,
    "Cache-Control": `private, max-age=${clientMaxAge}`,
    "X-Content-Type-Options": "nosniff",
  };

  if (etagMatches(request.headers.get("If-None-Match"), meta.etag)) {
    return new Response(null, { status: 304, headers: { ETag: meta.etag, "Cache-Control": base["Cache-Control"] } });
  }
  if (!request.headers.has("If-None-Match")) {
    const ims = Date.parse(request.headers.get("If-Modified-Since") ?? "");
    if (!Number.isNaN(ims) && Date.parse(meta.lastModified) <= ims) {
      return new Response(null, { status: 304, headers: { ETag: meta.etag, "Cache-Control": base["Cache-Control"] } });
    }
  }

  let range = parseRange(request.headers.get("Range"), meta.size);
  const ifRange = request.headers.get("If-Range");
  if (ifRange && range.kind !== "none" && ifRange.trim() !== meta.etag && ifRange.trim() !== meta.lastModified) {
    range = { kind: "none" }; // validator is stale: full representation
  }

  if (range.kind === "unsatisfiable") {
    return new Response(null, { status: 416, headers: { ...base, "Content-Range": `bytes */${meta.size}` } });
  }

  if (range.kind === "none") {
    if (request.method === "HEAD") {
      return new Response(null, { status: 200, headers: { ...base, "Content-Length": String(meta.size) } });
    }
    // Whole-object GET cannot be truncated (it must be a 200), so it streams straight from
    // the bucket binding, uncached. Players that seek send Range and take the cached path.
    const obj = await env.BUCKET.get(objectKey, { onlyIf: { etagMatches: meta.etag } });
    if (!obj || !("body" in obj) || !obj.body) return text(404, "not_found");
    return new Response(obj.body, {
      status: 200,
      headers: { ...base, "Content-Length": String(meta.size), "X-Edge-Cache": "BYPASS" },
    });
  }

  const start = range.start;
  const end = Math.min(range.end, start + MAX_SPAN - 1);
  const headers: Record<string, string> = {
    ...base,
    "Content-Range": `bytes ${start}-${end}/${meta.size}`,
    "Content-Length": String(end - start + 1),
  };
  if (request.method === "HEAD") return new Response(null, { status: 206, headers });

  const first = Math.floor(start / CHUNK_SIZE);
  const last = Math.floor(end / CHUNK_SIZE);
  const loader = (i: number) => loadChunk(env, ctx, deps, objectKey, meta, i, ttl);

  // Fetch the first chunk before answering, so an R2 failure is a real 5xx and the
  // cache status header is truthful for the bytes the client waits on.
  let firstChunk: { data: ArrayBuffer; hit: boolean };
  try {
    firstChunk = await loader(first);
  } catch {
    return text(502, "origin_error");
  }
  headers["X-Edge-Cache"] = firstChunk.hit ? "HIT" : "MISS";

  let idx = first;
  let pending: Promise<{ data: ArrayBuffer; hit: boolean }> | null = null;
  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const chunk = idx === first ? firstChunk : await pending!;
        // Start the next chunk before handing this one over: pipelines R2 with the client.
        pending = idx < last ? loader(idx + 1) : null;
        pending?.catch(() => {}); // surfaced at the next pull, not as an unhandled rejection
        const chunkStart = idx * CHUNK_SIZE;
        const from = Math.max(start, chunkStart) - chunkStart;
        const to = Math.min(end, chunkStart + chunk.data.byteLength - 1) - chunkStart;
        controller.enqueue(new Uint8Array(chunk.data, from, to - from + 1));
        if (idx === last) controller.close();
        idx++;
      } catch (e) {
        controller.error(e);
      }
    },
  });
  return new Response(body, { status: 206, headers });
}

const metaKey = (objectKey: string) => new Request(`${CACHE_ORIGIN}/m/${encodeURIComponent(objectKey)}`);
const chunkKey = (objectKey: string, i: number) =>
  new Request(`${CACHE_ORIGIN}/c/${CHUNK_SIZE}/${encodeURIComponent(objectKey)}/${i}`);

async function loadMeta(env: Env, ctx: ExecutionContext, deps: Deps, objectKey: string, ttl: number): Promise<Meta | null> {
  const hit = await deps.cache.match(metaKey(objectKey));
  if (hit) return (await hit.json()) as Meta;
  const head = await env.BUCKET.head(objectKey);
  if (!head) return null;
  const meta: Meta = {
    size: head.size,
    etag: head.httpEtag,
    lastModified: head.uploaded.toUTCString(),
    contentType: head.httpMetadata?.contentType ?? "application/octet-stream",
  };
  ctx.waitUntil(
    deps.cache
      .put(
        metaKey(objectKey),
        new Response(JSON.stringify(meta), { headers: { "Cache-Control": `public, max-age=${Math.min(ttl, 3600)}` } }),
      )
      .catch(() => {}),
  );
  return meta;
}

async function loadChunk(
  env: Env,
  ctx: ExecutionContext,
  deps: Deps,
  objectKey: string,
  meta: Meta,
  i: number,
  ttl: number,
): Promise<{ data: ArrayBuffer; hit: boolean }> {
  const key = chunkKey(objectKey, i);
  const hit = await deps.cache.match(key);
  // A chunk stamped with a different etag belongs to a previous object at this key: ignore it.
  if (hit && hit.headers.get("ETag") === meta.etag) return { data: await hit.arrayBuffer(), hit: true };

  const offset = i * CHUNK_SIZE;
  const length = Math.min(CHUNK_SIZE, meta.size - offset);
  const obj = await env.BUCKET.get(objectKey, { range: { offset, length } });
  if (!obj || !("body" in obj) || !obj.body) throw new Error("object_missing");
  if (obj.httpEtag !== meta.etag) throw new Error("object_changed");
  const data = await new Response(obj.body).arrayBuffer();
  if (data.byteLength !== length) throw new Error("short_read");
  ctx.waitUntil(
    deps.cache
      .put(
        key,
        new Response(data, {
          status: 200,
          headers: {
            ETag: meta.etag,
            "Content-Length": String(data.byteLength),
            "Cache-Control": `public, max-age=${ttl}`,
          },
        }),
      )
      .catch(() => {}),
  );
  return { data, hit: false };
}
