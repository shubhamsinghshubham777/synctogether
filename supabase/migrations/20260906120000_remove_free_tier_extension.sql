-- Remove session extension from the free tier:
-- Free tier rooms are capped at 4 hours flat.
-- Session extensions are an exclusive perk for Premium (up to 24 hours).

update public.tier_limits
set free_extension_minutes = 0
where tier = 'free';
