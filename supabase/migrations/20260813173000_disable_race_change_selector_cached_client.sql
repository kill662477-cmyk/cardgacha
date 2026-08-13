-- Emergency compatibility rollback: cached clients still fail when the new
-- balance/snapshot shape is enabled. Keep code deployed, but hide the feature
-- and restore the old snapshot contract until a versioned compatibility path exists.
begin;

do $balance$
declare
  v_config jsonb;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active
  for update;
  if v_config is null then raise exception 'active balance config missing'; end if;

  v_config := v_config
    #- '{directSupportItems,raceChangeSelector}'
    #- '{supportItems,raceChangeSelector}';

  update public.gacha_s2_balance_versions
  set config = v_config,
      config_hash = encode(digest(v_config::text, 'sha256'), 'hex')
  where active;
end;
$balance$;

do $snapshot_rollback$
declare
  v_def text;
  v_next text;
  v_fragment text := ', ''race'', coalesce(c.race_override, (select catalog.race from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id))';
begin
  select pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure) into v_def;
  v_next := replace(v_def, v_fragment, '');
  if v_next = v_def then
    raise exception 'player snapshot race rollback source mismatch';
  end if;
  execute v_next;
end;
$snapshot_rollback$;

do $verify$
declare
  v_config jsonb;
  v_snapshot_source text;
begin
  select config into v_config from public.gacha_s2_balance_versions where active;
  v_snapshot_source := pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure);
  if v_config->'directSupportItems' ? 'raceChangeSelector'
    or v_config->'supportItems' ? 'raceChangeSelector'
    or v_snapshot_source like '%c.race_override%' then
    raise exception 'race change selector cached-client disable verification failed';
  end if;
end;
$verify$;

commit;
