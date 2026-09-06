-- Align production free-tier media sharing limits with the product specification:
-- Weekly quota: 2.5 GB (2,684,354,560 bytes)
-- Max single file size: 2.0 GB (2,147,483,648 bytes)

update public.tier_limits
set media_sharing_weekly_bytes = 2684354560
where tier = 'free';

update public.app_settings
set value = jsonb_set(value, '{free_tier_max_file_bytes}', '2147483648'::jsonb)
where key = 'media_sharing';
