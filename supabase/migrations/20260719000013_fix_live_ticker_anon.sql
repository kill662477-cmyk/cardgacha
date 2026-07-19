begin;

grant select on table public.gacha_s2_live_events to anon;

drop policy if exists gacha_s2_live_events_recent_read on public.gacha_s2_live_events;
create policy gacha_s2_live_events_recent_read
  on public.gacha_s2_live_events
  for select
  to authenticated, anon
  using (created_at >= now() - interval '10 minutes');

commit;
