-- Migration: seed the media_edge switch (ships DISABLED).
--
-- When enabled, the media-share function's download-url returns a signed URL on the
-- media-edge Worker (docs/media-edge.md) instead of the S3 presigned URL. It also
-- needs the MEDIA_EDGE_SECRET function secret; without both, behaviour is unchanged.
-- chunk_bytes / max_parallel are hints returned beside streamUrl for the client's
-- range fetcher: default 8 MiB (allowed 4-32 MiB, multiple of 4 MiB) and 4 (1-8).
-- Out-of-range values are clamped by the function, not rejected.
-- Config, not a constant: update public.app_settings where key = 'media_edge'.

insert into public.app_settings (key, value)
values ('media_edge', '{"enabled": false, "base_url": null, "chunk_bytes": 8388608, "max_parallel": 4}'::jsonb)
on conflict (key) do nothing;
