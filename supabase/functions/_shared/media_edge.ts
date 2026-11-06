// Edge delivery URLs for shared media (deploy/media-edge, docs/media-edge.md).
// Scheme must match deploy/media-edge/src/sign.ts; both carry the same test vector.
//   message = `${objectKey}\n${exp}`, sig = base64url(HMAC-SHA256(secret, message))

export type EdgeConfig = { baseUrl: string; secret: string; chunkBytes: number; maxParallel: number };

const MIB = 1024 * 1024;
/** Must equal CHUNK_SIZE in deploy/media-edge/src/index.ts: client chunks are whole multiples of it. */
export const WORKER_CHUNK_BYTES = 4 * MIB;
export const CHUNK_BYTES_DEFAULT = 8 * MIB;
export const CHUNK_BYTES_MAX = 32 * MIB;
export const MAX_PARALLEL_DEFAULT = 4;
export const MAX_PARALLEL_MAX = 8;

/** `chunk_bytes` hint: default 8 MiB, clamped to 4-32 MiB and rounded down to a multiple of 4 MiB. */
export function clampChunkBytes(v: unknown): number {
  if (typeof v !== "number" || !Number.isFinite(v)) return CHUNK_BYTES_DEFAULT;
  const steps = Math.floor(v / WORKER_CHUNK_BYTES);
  return Math.min(CHUNK_BYTES_MAX, Math.max(WORKER_CHUNK_BYTES, steps * WORKER_CHUNK_BYTES));
}

/** `max_parallel` hint: default 4, clamped to 1-8. */
export function clampMaxParallel(v: unknown): number {
  if (typeof v !== "number" || !Number.isFinite(v)) return MAX_PARALLEL_DEFAULT;
  return Math.min(MAX_PARALLEL_MAX, Math.max(1, Math.floor(v)));
}

/**
 * Edge delivery is used only when the `media_edge` app_settings row says
 * `enabled: true` with an https `base_url` AND the MEDIA_EDGE_SECRET secret exists.
 * `chunk_bytes` / `max_parallel` are optional tuning hints for the client (clamped here).
 * Anything else returns null and the caller falls back to the S3 presigned URL.
 */
export function resolveEdgeConfig(setting: unknown, secret: string | undefined | null): EdgeConfig | null {
  if (!secret) return null;
  if (typeof setting !== "object" || setting === null) return null;
  const s = setting as Record<string, unknown>;
  if (s.enabled !== true || typeof s.base_url !== "string") return null;
  let url: URL;
  try {
    url = new URL(s.base_url);
  } catch {
    return null;
  }
  const local = url.hostname === "localhost" || url.hostname === "127.0.0.1";
  if (url.protocol !== "https:" && !(local && url.protocol === "http:")) return null;
  return {
    baseUrl: url.origin + url.pathname.replace(/\/+$/, ""),
    secret,
    chunkBytes: clampChunkBytes(s.chunk_bytes),
    maxParallel: clampMaxParallel(s.max_parallel),
  };
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function signEdgeToken(secret: string, objectKey: string, exp: number): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  return b64url(new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(`${objectKey}\n${exp}`))));
}

/** `ttlSeconds` is the same TTL the presigned URL would get; exp is absolute unix seconds. */
export async function buildEdgeUrl(
  cfg: EdgeConfig,
  objectKey: string,
  ttlSeconds: number,
  nowMs: number = Date.now(),
): Promise<string> {
  const exp = Math.floor(nowMs / 1000) + ttlSeconds;
  const sig = await signEdgeToken(cfg.secret, objectKey, exp);
  const path = objectKey.split("/").map(encodeURIComponent).join("/");
  return `${cfg.baseUrl}/v1/${path}?exp=${exp}&sig=${sig}`;
}
