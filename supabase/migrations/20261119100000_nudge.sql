-- "Remind Sam": one gentle push from one half of a pair to the other, from the
-- Pre-show check, when the film is ready on this side and the partner has not
-- opened the app yet (boards 94e D and K).
--
--   * kind `date_night_nudge`: gated by the existing `push_prefs.date_nights`
--     switch (push_kind_enabled maps every `date_night%` kind to it), so there
--     is no new column and no change to my_push_prefs / set_push_pref.
--   * One per night every ten minutes, counted from the outbox (sent or not),
--     so a held-down button cannot become a barrage. Quiet hours apply:
--     claim_push_batch exempts only calls.
--   * Only for an accepted night of this pair that is around now: from three
--     hours after it began to a day before it starts. A nudge for a night next
--     month, or one long over, is not a nudge.
--   * Android uses its default channel (it is an update, not "someone sat down").

create or replace function public.nudge_partner(p_night_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pair uuid := public.my_pair_id();
  v_partner uuid;
  v_night public.date_nights;
begin
  if v_uid is null or v_pair is null then
    raise exception 'not_paired';
  end if;

  select * into v_night from public.date_nights
    where id = p_night_id and pair_id = v_pair;
  if not found or v_night.status <> 'accepted' then
    return jsonb_build_object('sent', false, 'reason', 'no_night');
  end if;
  if v_night.starts_at < now() - interval '3 hours'
     or v_night.starts_at > now() + interval '1 day' then
    return jsonb_build_object('sent', false, 'reason', 'not_now');
  end if;

  v_partner := public.partner_of(v_uid);

  if exists (select 1 from public.push_outbox
             where user_id = v_partner and kind = 'date_night_nudge'
               and data->>'night' = p_night_id::text
               and created_at > now() - interval '10 minutes') then
    return jsonb_build_object('sent', false, 'reason', 'throttled');
  end if;

  -- A nudge still waiting to go out (quiet hours) is replaced, never doubled.
  -- Removed first, not left to enqueue_push's upsert: the upsert keeps the old
  -- row's created_at, and the throttle above counts from created_at.
  perform public.cancel_push('nudge:' || p_night_id::text);
  perform public.enqueue_push(
    v_partner, 'date_night_nudge',
    public.partner_label(v_partner, v_uid) || ' is ready for ' || v_night.title,
    'The film is ready on their side. Open SyncTogether to get your seat.',
    jsonb_build_object('route', 'lobby', 'night', p_night_id),
    now(), now() + interval '2 hours', 'nudge:' || p_night_id::text);
  return jsonb_build_object('sent', true);
end $$;

revoke execute on function public.nudge_partner(uuid) from public, anon;
grant execute on function public.nudge_partner(uuid) to authenticated;
