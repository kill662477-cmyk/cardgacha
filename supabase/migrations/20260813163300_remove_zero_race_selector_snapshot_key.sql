-- Cached clients reject unknown support-item keys during startup.
-- No account owns this item yet, so remove only zero-valued placeholders from snapshots.
begin;

update public.gacha_s2_player_states
set support_items = support_items - 'raceChangeSelector',
    updated_at = now()
where support_items ? 'raceChangeSelector'
  and coalesce((support_items->>'raceChangeSelector')::integer, 0) = 0;

do $$
begin
  if exists (
    select 1
    from public.gacha_s2_player_states
    where support_items ? 'raceChangeSelector'
      and coalesce((support_items->>'raceChangeSelector')::integer, 0) = 0
  ) then
    raise exception 'ZERO_RACE_SELECTOR_SNAPSHOT_KEY_CLEANUP_FAILED';
  end if;
end;
$$;

commit;
