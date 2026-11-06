import { beforeEach, describe, expect, it } from "vitest";
import { CHUNK_SIZE, handle, MAX_SPAN, objectKeyFromPath, type Env } from "../src/index";
import { signToken } from "../src/sign";

const SECRET = "s3cret";
const NOW = 1_800_000_000_000;
const KEY = "users/u1/room/r1/movie.mkv";
const SIZE = 10 * CHUNK_SIZE + 123; // 11 chunks, last one short

const bytes = new Uint8Array(SIZE);
for (let i = 0; i < SIZE; i++) bytes[i] = (i * 31 + (i >> 8)) & 255;

class FakeBucket {
  gets = 0;
  heads = 0;
  etag = '"e1"';
  objects = new Map<string, Uint8Array>([[KEY, bytes]]);
  async head(key: string) {
    this.heads++;
    const o = this.objects.get(key);
    return o && { size: o.length, httpEtag: this.etag, uploaded: new Date(NOW - 1000), httpMetadata: { contentType: "video/x-matroska" } };
  }
  async get(key: string, opts?: { range?: { offset: number; length: number }; onlyIf?: unknown }) {
    this.gets++;
    const o = this.objects.get(key);
    if (!o) return null;
    const r = opts?.range;
    const slice = r ? o.slice(r.offset, r.offset + r.length) : o;
    return { httpEtag: this.etag, body: new Blob([slice]).stream() };
  }
}

class FakeCache {
  store = new Map<string, Response>();
  async match(req: Request) {
    return this.store.get(req.url)?.clone();
  }
  async put(req: Request, res: Response) {
    if (res.status === 206) throw new Error("206 is not cacheable");
    this.store.set(req.url, res);
  }
}

let bucket: FakeBucket;
let cache: FakeCache;
const pending: Promise<unknown>[] = [];
const ctx = { waitUntil: (p: Promise<unknown>) => void pending.push(p) } as unknown as ExecutionContext;
const env = () => ({ BUCKET: bucket as unknown as R2Bucket, MEDIA_EDGE_SECRET: SECRET }) as Env;

async function call(headers: Record<string, string> = {}, opts: { method?: string; key?: string; sig?: string; exp?: number } = {}) {
  const key = opts.key ?? KEY;
  const exp = opts.exp ?? NOW / 1000 + 3600;
  const sig = opts.sig ?? (await signToken(SECRET, key, exp));
  const path = key.split("/").map(encodeURIComponent).join("/");
  const req = new Request(`https://media.example/v1/${path}?exp=${exp}&sig=${sig}`, { method: opts.method ?? "GET", headers });
  const res = await handle(req, env(), ctx, { cache: cache as unknown as Cache, now: () => NOW });
  await Promise.all(pending.splice(0));
  return res;
}
const body = async (r: Response) => new Uint8Array(await r.arrayBuffer());

beforeEach(() => {
  bucket = new FakeBucket();
  cache = new FakeCache();
});

describe("auth", () => {
  it("400 malformed, 403 forged and expired, 405 other methods, 404 bad path", async () => {
    expect((await call({}, { sig: "abc" })).status).toBe(400);
    expect((await call({}, { sig: "A".repeat(43) })).status).toBe(403);
    const expired = await call({}, { exp: NOW / 1000 - 5 });
    expect(expired.status).toBe(403);
    expect(((await expired.json()) as { error: string }).error).toBe("expired");
    expect((await call({}, { method: "POST" })).status).toBe(405);
    const bad = await handle(new Request("https://m/v1/a/%2e%2e%2fb?exp=1&sig=x"), env(), ctx, { cache: cache as unknown as Cache, now: () => NOW });
    expect(bad.status).toBe(404);
    expect(bucket.gets + bucket.heads).toBe(0); // nothing reaches R2 before the token checks out
  });
  it("a token for one object does not open another", async () => {
    bucket.objects.set("users/u2/other.mkv", new Uint8Array(10));
    const exp = NOW / 1000 + 100;
    const sig = await signToken(SECRET, KEY, exp);
    const res = await call({}, { key: "users/u2/other.mkv", sig, exp });
    expect(res.status).toBe(403);
  });
  it("404 for a valid token on a missing object", async () => {
    expect((await call({}, { key: "users/u1/none.mkv" })).status).toBe(404);
  });
});

describe("ranges", () => {
  it("serves an exact byte range across a chunk boundary", async () => {
    const start = CHUNK_SIZE - 10;
    const res = await call({ Range: `bytes=${start}-${start + 99}` });
    expect(res.status).toBe(206);
    expect(res.headers.get("Content-Range")).toBe(`bytes ${start}-${start + 99}/${SIZE}`);
    expect(res.headers.get("Content-Length")).toBe("100");
    expect(res.headers.get("Accept-Ranges")).toBe("bytes");
    expect(res.headers.get("ETag")).toBe('"e1"');
    expect(res.headers.get("Cache-Control")).toMatch(/^private, max-age=\d+$/);
    expect(await body(res)).toEqual(bytes.slice(start, start + 100));
  });
  it("suffix range and the short final chunk", async () => {
    const res = await call({ Range: "bytes=-200" });
    expect(res.status).toBe(206);
    expect(await body(res)).toEqual(bytes.slice(SIZE - 200));
  });
  it("open-ended range is truncated to MAX_SPAN, with an honest Content-Range", async () => {
    const res = await call({ Range: "bytes=5-" });
    expect(res.status).toBe(206);
    expect(res.headers.get("Content-Range")).toBe(`bytes 5-${5 + MAX_SPAN - 1}/${SIZE}`);
    const got = await body(res);
    expect(got.length).toBe(MAX_SPAN);
    expect(got[MAX_SPAN - 1]).toBe(bytes[5 + MAX_SPAN - 1]);
  });
  it("416 with Content-Range */size", async () => {
    const res = await call({ Range: `bytes=${SIZE}-` });
    expect(res.status).toBe(416);
    expect(res.headers.get("Content-Range")).toBe(`bytes */${SIZE}`);
  });
  it("HEAD with Range returns headers only", async () => {
    const res = await call({ Range: "bytes=0-9" }, { method: "HEAD" });
    expect(res.status).toBe(206);
    expect(res.headers.get("Content-Length")).toBe("10");
    expect((await body(res)).length).toBe(0);
    expect(bucket.gets).toBe(0);
  });
  it("If-Range with a stale validator falls back to 200", async () => {
    const res = await call({ Range: "bytes=0-9", "If-Range": '"old"' });
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Length")).toBe(String(SIZE));
    await res.body?.cancel();
    const ok = await call({ Range: "bytes=0-9", "If-Range": '"e1"' });
    expect(ok.status).toBe(206);
  });
  it("If-None-Match gives 304", async () => {
    expect((await call({ "If-None-Match": '"e1"' })).status).toBe(304);
  });
});

describe("edge cache", () => {
  it("the second viewer is served from cache without touching R2 chunks", async () => {
    const r1 = await call({ Range: "bytes=0-1023" });
    expect(r1.headers.get("X-Edge-Cache")).toBe("MISS");
    await body(r1);
    const getsAfterFirst = bucket.gets;
    const headsAfterFirst = bucket.heads;

    // Different token (different exp, so different sig): same canonical key.
    const r2 = await call({ Range: "bytes=100-2000" }, { exp: NOW / 1000 + 7200 });
    expect(r2.headers.get("X-Edge-Cache")).toBe("HIT");
    expect(await body(r2)).toEqual(bytes.slice(100, 2001));
    expect(bucket.gets).toBe(getsAfterFirst);
    expect(bucket.heads).toBe(headsAfterFirst);
  });
  it("cache keys never contain the token", async () => {
    await body(await call({ Range: "bytes=0-9" }));
    for (const k of cache.store.keys()) expect(k).not.toMatch(/sig=|exp=/);
  });
  it("chunks are keyed per object", async () => {
    bucket.objects.set("users/u1/b.mkv", new Uint8Array(5000).fill(7));
    await body(await call({ Range: "bytes=0-9" }));
    const b = await call({ Range: "bytes=0-9" }, { key: "users/u1/b.mkv" });
    expect(b.headers.get("X-Edge-Cache")).toBe("MISS");
    expect(await body(b)).toEqual(new Uint8Array(10).fill(7));
  });
  it("a replaced object (new etag) never serves stale cached chunks", async () => {
    await body(await call({ Range: "bytes=0-9" }));
    cache.store.delete([...cache.store.keys()].find((k) => k.includes("/m/"))!); // meta expired, chunk still cached
    bucket.etag = '"e2"';
    bucket.objects.set(KEY, new Uint8Array(SIZE).fill(1));
    const res = await call({ Range: "bytes=0-9" });
    expect(res.headers.get("X-Edge-Cache")).toBe("MISS");
    expect(await body(res)).toEqual(new Uint8Array(10).fill(1));
  });
});

describe("objectKeyFromPath", () => {
  it("decodes and rejects traversal", () => {
    expect(objectKeyFromPath("/v1/users/a%20b/c.mkv")).toBe("users/a b/c.mkv");
    expect(objectKeyFromPath("/v1/a%2f..%2fb")).toBeNull();
    expect(objectKeyFromPath("/v1/a//b")).toBeNull();
    expect(objectKeyFromPath("/v2/a")).toBeNull();
    expect(objectKeyFromPath("/v1/")).toBeNull();
  });
});

describe("abuse limits and metrics", () => {
  const limiter = (allow: boolean, seen: string[]) =>
    ({ limit: async ({ key }: { key: string }) => (seen.push(key), { success: allow }) }) as unknown as RateLimit;

  async function withEnv(extra: Partial<Env>, headers: Record<string, string> = {}) {
    const exp = NOW / 1000 + 3600;
    const sig = await signToken(SECRET, KEY, exp);
    const path = KEY.split("/").map(encodeURIComponent).join("/");
    const req = new Request(`https://media.example/v1/${path}?exp=${exp}&sig=${sig}`, { headers: { Range: "bytes=0-9", ...headers } });
    const res = await handle(req, { ...env(), ...extra }, ctx, { cache: cache as unknown as Cache, now: () => NOW });
    await Promise.all(pending.splice(0));
    return { res, sig };
  }

  it("429 with Retry-After when the token limiter refuses, before any R2 work", async () => {
    const seen: string[] = [];
    const { res, sig } = await withEnv({ TOKEN_LIMITER: limiter(false, seen) });
    expect(res.status).toBe(429);
    expect(res.headers.get("Retry-After")).toBe("15");
    expect(seen).toEqual([sig]);
    expect(bucket.heads + bucket.gets).toBe(0);
  });
  it("429 when the IP limiter refuses, keyed on CF-Connecting-IP", async () => {
    const seen: string[] = [];
    const { res } = await withEnv({ IP_LIMITER: limiter(false, seen) }, { "CF-Connecting-IP": "203.0.113.9" });
    expect(res.status).toBe(429);
    expect(seen).toEqual(["203.0.113.9"]);
  });
  it("forged tokens never reach the limiters", async () => {
    const seen: string[] = [];
    const req = new Request(`https://media.example/v1/${KEY}?exp=${NOW / 1000 + 60}&sig=${"A".repeat(43)}`);
    const res = await handle(req, { ...env(), TOKEN_LIMITER: limiter(true, seen) }, ctx, { cache: cache as unknown as Cache, now: () => NOW });
    expect(res.status).toBe(403);
    expect(seen).toEqual([]);
  });
  it("allowed requests pass and write one data point without URL or token", async () => {
    const points: unknown[] = [];
    const METRICS = { writeDataPoint: (p: unknown) => void points.push(p) } as unknown as AnalyticsEngineDataset;
    const { res } = await withEnv({ METRICS, TOKEN_LIMITER: limiter(true, []) });
    expect(res.status).toBe(206);
    expect(points).toEqual([{ indexes: ["media-edge"], blobs: ["206", "MISS", "GET"], doubles: [10] }]);
  });
  it("a throwing metrics binding never breaks delivery", async () => {
    const METRICS = { writeDataPoint: () => { throw new Error("boom"); } } as unknown as AnalyticsEngineDataset;
    expect((await withEnv({ METRICS })).res.status).toBe(206);
  });
});
