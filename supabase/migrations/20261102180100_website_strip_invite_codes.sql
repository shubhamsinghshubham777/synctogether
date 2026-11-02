-- /join/<code> pageviews were stored with the invite code in the path. A code
-- is the join credential for a live room, and analytics has no use for it, so
-- the collector now files these as /join/* (website/lib/web-events.ts) and this
-- scrubs what was already written. It also makes top_paths_30d meaningful:
-- every room used to be its own one-view "path".

update public.website_pageviews
set pathname = regexp_replace(pathname, '^/join/[^/?#]+', '/join/*')
where pathname like '/join/%' and pathname <> '/join/*';

update public.website_visitors
set first_path = regexp_replace(first_path, '^/join/[^/?#]+', '/join/*')
where first_path like '/join/%' and first_path <> '/join/*';
