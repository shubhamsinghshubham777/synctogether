# Media edge: fast streaming of shared videos

Runbook for `deploy/media-edge/` and the `media_edge` flag. Nothing here is deployed by CI. The Worker only *delivers* the host's original bytes (no transcoding, no rewriting); quality is unchanged.

## What and why

Without it, members stream a presigned URL on `<account>.r2.cloudflarestorage.com`: not CDN-cached, unique query string per URL, every viewer is served from the R2 origin. With it, `download-url` returns `https://media.<domain>/v1/<objectKey>?exp=<unix>&sig=<HMAC>` and the Worker:

1. verifies the HMAC (constant time), rejects expired or too-far-future tokens;
2. reads the object through the **R2 bucket binding** (no S3 credentials in the Worker);
3. answers HTTP Range (single, open-ended, suffix; 206/416, `If-Range`, `If-None-Match`, `ETag`, `Last-Modified`);
4. caches **aligned 4 MiB chunks** in the Workers Cache API under `object key + chunk index` (the token is never in the key), so viewer 2..N in the same data centre never touch R2.

Each 206 carries at most 36 MiB; a longer open-ended request gets a shorter, correctly labelled 206 and the player asks again. A Range-less GET streams straight from R2, uncached (a 200 cannot be truncated).

## Recommendation: A (Worker + Cache API chunks) over B (custom domain + WAF HMAC)

| | A. Worker + Cache API | B. R2 custom domain + Cache Rules + `is_timed_hmac_valid_v0` |
|---|---|---|
| Plan needed | Workers Paid ($5/mo) recommended; works on Free for light use | **WAF HMAC needs Pro or higher** (zone `synctogether.app` is on Free). Cloudflare's own doc: presigned URLs do not work on custom domains; HMAC is the stated alternative |
| 10 GB files | Fine: chunks are 4 MiB, memory bounded to two chunks | CDN cacheable-file limit is **512 MB on Free/Pro/Business** (5 GB Enterprise). Whether Origin Range Requests lets partial caching of larger files work was not verifiable from docs; do not rely on it |
| Access control | Bucket stays private; Worker holds a binding | Bucket must be public on a custom domain; the only gate is the WAF rule, so a rule mistake exposes every upload |
| Per-viewer cost | Worker request + Cache API calls; R2 Class B read only on a miss | Cache HIT is free of Worker cost |
| Cache sharing | Per data centre (Cache API is not tiered) | CDN tiered cache available |
| Moving parts | One Worker, one secret | DNS + cache rule + WAF rule + Pro plan |

Evidence (Cloudflare docs): `cache.put` throws on 206 and Workers Cache never stores a Worker-returned 206, so partial responses are cached as full 200 chunk objects and re-sliced; cacheable size 512 MB on Free/Pro/Business; `is_timed_hmac_valid_v0` requires Pro+; Workers Free allows 10 ms CPU and 50 subrequests (Cache API calls share the quota, 1000 on Paid), Paid allows far more. B becomes attractive only if the zone moves to Pro **and** files stay under 512 MB; it is not implemented. If you ever take B: attach a custom domain to the bucket, add a Cache Rule (cache everything, Origin Range Requests on), and a WAF custom rule blocking requests where `not is_timed_hmac_valid_v0(...)`; the signer would then have to emit Cloudflare's `<ts>-<mac>` format instead of ours.

## Deploy (user-approved steps only)

```bash
cd deploy/media-edge && npm install && npm test
npx wrangler login

# 1. Secret, same value on both sides
SECRET=$(openssl rand -base64 48)
printf '%s' "$SECRET" | npx wrangler secret put MEDIA_EDGE_SECRET
supabase secrets set MEDIA_EDGE_SECRET="$SECRET"

# 2. Worker (check bucket_name in wrangler.toml equals CF_R2_BUCKET_NAME)
#    Uncomment [[routes]] with your hostname, custom_domain = true
npx wrangler deploy
```

DNS: with `custom_domain = true`, wrangler creates the proxied DNS record and certificate for `media.<domain>` on a zone in your account (for synctogether.app that is `media.synctogether.app`; the zone currently has no `media` record). Leave `workers_dev` off.

Enable (instant, no deploy, no app release):

```sql
update public.app_settings
   set value = '{"enabled": true, "base_url": "https://media.synctogether.app"}'::jsonb
 where key = 'media_edge';
```

`media-share` reads the row on every `download-url` call, so this takes effect at once. Ship the function code first with `supabase functions deploy media-share`.

## Verify

```bash
URL='https://media.<domain>/v1/<key>?exp=<exp>&sig=<sig>'   # copy a streamUrl from download-url
curl -sI "$URL"                                              # 200, Accept-Ranges: bytes, ETag, Content-Length
curl -s -D- -o /dev/null -H 'Range: bytes=0-1023' "$URL"    # 206, Content-Range: bytes 0-1023/<size>, X-Edge-Cache: MISS
curl -s -D- -o /dev/null -H 'Range: bytes=0-1023' "$URL"    # now X-Edge-Cache: HIT
curl -s -D- -o /dev/null -H 'Range: bytes=-1024' "$URL"     # suffix range
curl -s -D- -o /dev/null -H "Range: bytes=99999999999-" "$URL"  # 416, Content-Range: bytes */<size>
curl -s -o /dev/null -w '%{http_code}\n' "${URL%&sig=*}&sig=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"   # 403 tampered
curl -s -o /dev/null -w '%{http_code}\n' "https://media.<domain>/v1/<key>?exp=1&sig=x"                      # 400 malformed
# expired: sign with a past exp (403, {"error":"expired"})
```

The HIT is per data centre, so repeat from a second region to see a fresh MISS. `wrangler tail` and invocation logs are off on purpose: they record the URL, which carries the token.

## Rollback

`update public.app_settings set value = jsonb_set(value,'{enabled}','false') where key='media_edge';` New `download-url` calls return presigned S3 URLs immediately; an edge URL already in a client keeps working until its `exp` (at most 24 h), or until you `wrangler delete`. Rotating `MEDIA_EDGE_SECRET` on the Worker alone invalidates every outstanding edge URL at once (clients re-sign on 403).

## Client hints: chunk size and parallelism

With the edge on, `download-url` adds two optional fields beside the unchanged `streamUrl` (older clients ignore them), sourced from `app_settings.media_edge`:

| Field | Setting key | Default | Allowed | Rule |
|---|---|---|---|---|
| `chunkBytes` | `chunk_bytes` | 8 MiB | 4-32 MiB | rounded down to a multiple of 4 MiB, anything else clamps/defaults |
| `maxParallel` | `max_parallel` | 4 | 1-8 | clamped |

Why a *multiple of 4 MiB*: the Worker reads and caches 4 MiB chunks (`CHUNK_SIZE`). A client chunk aligned to its own size is therefore an exact run of whole Worker chunks, so one client chunk is one Worker request. `MAX_SPAN` is 36 MiB (9 chunks) so even a misaligned 32 MiB request is answered whole. If you change `CHUNK_SIZE`, change `WORKER_CHUNK_BYTES` in `supabase/functions/_shared/media_edge.ts` with it. Tune live, no deploy: `update public.app_settings set value = value || '{"chunk_bytes": 16777216, "max_parallel": 6}' where key = 'media_edge';`. The presigned fallback never carries these fields.

## Abuse limits (optional, per token and per IP)

Two Workers Rate Limiting bindings (`TOKEN_LIMITER` keyed on the signature, `IP_LIMITER` keyed on `CF-Connecting-IP`), commented out in `wrangler.toml`. Why this and not something heavier: it is a binding call with no storage to run (a Durable Object per token would cost a request plus duration per chunk), it is GA, and the docs do not restrict it to a paid plan (I could not confirm Free-plan availability or any separate price; check the pricing page before relying on it). Honest limits: counts are per data centre and approximate, the period is 10 or 60 s, and a limit can be briefly exceeded. They run only after the HMAC passes, so forged traffic cannot drain a real viewer's allowance. Defaults (600/min per token, 1200/min per IP) allow about 5 GB/min per token. Unauthenticated floods are not counted here; if they matter, add a WAF rate-limiting rule on `media.<domain>` (zone-level, plan limits apply). A refused request gets `429` with `Retry-After: 15`.

## Usage visibility (optional, off by default)

Uncomment `[[analytics_engine_datasets]]` (binding `METRICS`) to write one non-blocking data point per request: blobs `[status, HIT|MISS|BYPASS|NA, method]`, double `[Content-Length]`. No URL, key or token. Bytes are the length promised, not what a disconnecting player actually pulled. Query it with the Analytics Engine SQL API. **Cost is unverified**: my documentation search did not surface Analytics Engine's pricing or free allowance, so confirm it on the pricing page before enabling. Without it, the free alternatives are the Worker's metrics tab (requests, errors, CPU) and R2's bucket metrics (operations), which cover cost tracking but not HIT ratio.

## Cost and scaling

Prices (Cloudflare docs, fetched 2026-11-06): Workers Paid $5/month includes 10 M requests and 30 M CPU-ms, then $0.30 per M requests and $0.02 per M CPU-ms; R2 Standard $0.015/GB-month, Class B reads $0.36/M (10 M/month free), Class A $4.50/M, **egress free**; a cache hit still counts as a Worker request.

What scales: Worker requests = bytes streamed / client `chunkBytes`; R2 Class B reads = cache-miss bytes / 4 MiB. Bytes themselves cost nothing. Assumptions (all mine, adjust to reality): a viewing streams 4 GiB, 8 MiB client chunks, 75 % of 4 MiB chunks served from cache (a room of about four members in one region), 4 ms CPU per request (unmeasured; measure after deploy).

| Viewings per day | Worker requests/mo | R2 reads/mo (miss) | Workers requests | CPU | R2 Class B | Monthly total |
|---|---|---|---|---|---|---|
| 1,000 | 15 M | 8 M | $6.6 (incl. $5 plan) | $0.6 | $0 (free tier) | about $7 |
| 10,000 | 154 M | 77 M | $48 | $12 | $24 | about $84 |
| 100,000 | 1.5 B | 0.77 B | $463 | $122 | $273 | about $858 |

Levers, in order of effect:

1. **Client chunk size** (`chunk_bytes`): requests fall in proportion. At 100k/day, 32 MiB chunks cut the Worker request line from $463 to $117 and total to about $420, at the price of more bytes fetched and discarded on a seek (Worker memory stays bounded: it buffers at most two 4 MiB chunks per request regardless).
2. **Hit ratio**: halving it to 50 % lifts R2 reads to $549 at 100k/day (about $1,130 total). Rooms where members watch together hit best.
3. **Worker `CHUNK_SIZE`** (4 MiB): 8 MiB halves R2 reads but over-fetches on seeks; change it together with `WORKER_CHUNK_BYTES`.
4. `maxParallel` does not change totals, only burstiness; keep request counts frugal by having the client coalesce adjacent chunks and not prefetch far ahead.

**No-Worker alternative (zone Cache Rules, option B in the table above).** Cache hits cost no Worker request, which removes the dominant line at scale, but it needs an R2 custom domain on a public bucket, Pro or higher for `is_timed_hmac_valid_v0`, and the CDN's 512 MB cacheable-file limit (Free/Pro/Business; 5 GB Enterprise) rules out the 10 GB files. If most shared files were under 512 MB and traffic reached the 100k/day tier, a Pro zone ($25/month, 2026 list price, verify) plus Cache Rules could be cheaper than the Worker. Re-evaluate then; it needs a signer for Cloudflare's token format.

**Billing safety.** Workers has no hard spending cap. Do all of these before enabling for real traffic: set usage-based billing notifications in the dashboard (Notifications, Billing; set thresholds for Workers and R2), keep the Rate Limiting bindings on, set `limits.cpu_ms` in `wrangler.toml` to bound a single invocation, and remember the kill switch is instant: `update public.app_settings set value = jsonb_set(value,'{enabled}','false') where key='media_edge';` stops *new* edge URLs at once, and `wrangler delete` stops existing ones.

## Limits and honest caveats

- Cache is per data centre; the first viewer in each region pays an R2 read (4 MiB chunk, one Class B op). R2 egress is free.
- Deleted/expired shared videos can stay in a colo's cache for up to `EDGE_CACHE_TTL_SECONDS` (default 21600 s); tokens still gate access, but a takedown is not instant at the edge. Purge by changing the object key (new upload) or `wrangler delete`.
- `MAX_TTL_SECONDS` (default 90000) rejects tokens with an `exp` further out than that; the function issues at most 86400.
- First byte of a cold range waits for one whole 4 MiB chunk. Chunk size and span are `CHUNK_SIZE`/`MAX_SPAN` in `src/index.ts`.

## R2 location hint

Read-only inspection (Cloudflare API, 2026-11-06): account `e503fba2...` holds one bucket, `synctogether-media`, **location APAC, storage class Standard, jurisdiction default**, created 2026-08-30, no custom domains attached. A bucket's location hint is fixed at creation. APAC is right for an Asia-heavy audience and costs Europe/US viewers extra latency on a cache miss only; the edge cache hides most of that after the first viewer per region. If your members are mostly elsewhere, migrate:

1. Create a new bucket with a hint (`npx wrangler r2 bucket create synctogether-media-eu --location weur`; hints are `wnam enam weur eeur apac oc`).
2. Shared videos are short-lived (room length + 2 h) so the simplest path is **no copy**: point `CF_R2_BUCKET_NAME` (and `CF_R2_ENDPOINT` if jurisdictional) at the new bucket and the Worker binding's `bucket_name` at it, deploy both, and let the old bucket drain through `cleanup-r2` (it needs the old name until `pending_r2_deletions` empties; keep the old bucket until then). Rooms with a ready video at the switch lose it, so do it off-peak.
3. To carry data over instead: `rclone copy` between the two R2 S3 endpoints, or R2 Super Slurper / Sippy (incremental, copies on first read).
4. Cost: R2 storage $0.015/GB-month Standard, no egress fees, Class A $4.50/M and Class B $0.36/M; a migration of a few GB is cents. Cross-bucket copies are Class A/B ops only.
