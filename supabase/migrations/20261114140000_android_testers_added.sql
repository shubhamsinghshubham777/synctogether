-- When a tester was put on the Play Console tester list. Null = signed up, not added yet.
-- The public seat check reads it (through the service role) to say "opt in now".
alter table public.android_testers add column if not exists added_at timestamptz;
