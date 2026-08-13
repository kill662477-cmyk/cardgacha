-- Re-enable the race selector without adding an unknown zero-valued item key to every account.
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

  v_config := jsonb_set(v_config, '{directSupportItems}', coalesce(v_config->'directSupportItems', '{}'::jsonb), true);
  v_config := jsonb_set(
    v_config,
    '{directSupportItems,raceChangeSelector}',
    '{"name":"종족선택 변경권","price":20000000}'::jsonb,
    true
  );
  v_config := jsonb_set(
    v_config,
    '{supportItems,raceChangeSelector}',
    '{"name":"종족선택 변경권","category":"종족","effect":"보유 카드 1종을 원하는 시너지 종족으로 변경","raceSelector":true,"hideWhenEmpty":true}'::jsonb,
    true
  );

  update public.gacha_s2_balance_versions
  set config = v_config,
      config_hash = encode(digest(v_config::text, 'sha256'), 'hex')
  where active;
end;
$balance$;

do $snapshot_patch$
declare
  v_def text;
  v_next text;
  v_source text := '''archetype'', coalesce(c.archetype_override, (select catalog.archetype from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id))';
  v_race_fragment text := ', ''race'', coalesce(c.race_override, (select catalog.race from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id))';
begin
  select pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure) into v_def;
  if strpos(v_def, v_race_fragment) = 0 then
    v_next := replace(v_def, v_source, v_source || v_race_fragment);
    if v_next = v_def or strpos(v_next, v_race_fragment) = 0 then
      raise exception 'player snapshot race patch source mismatch';
    end if;
    execute v_next;
  end if;
end;
$snapshot_patch$;

-- Keep zero-count placeholders out of snapshots for cached clients.
create or replace function public.gacha_s2_strip_zero_race_selector_key()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.support_items ? 'raceChangeSelector'
     and coalesce((new.support_items->>'raceChangeSelector')::integer, 0) <= 0 then
    new.support_items := new.support_items - 'raceChangeSelector';
  end if;
  return new;
end;
$$;

drop trigger if exists gacha_s2_strip_zero_race_selector_key_trigger
  on public.gacha_s2_player_states;
create trigger gacha_s2_strip_zero_race_selector_key_trigger
before insert or update of support_items on public.gacha_s2_player_states
for each row execute function public.gacha_s2_strip_zero_race_selector_key();

revoke all on function public.gacha_s2_strip_zero_race_selector_key() from public, anon, authenticated;

-- Defensive cleanup in case a zero placeholder was written between the emergency cleanup and this migration.
update public.gacha_s2_player_states
set support_items = support_items - 'raceChangeSelector',
    updated_at = now()
where support_items ? 'raceChangeSelector'
  and coalesce((support_items->>'raceChangeSelector')::integer, 0) <= 0;

do $verify$
declare
  v_config jsonb;
  v_snapshot_source text;
begin
  select config into v_config from public.gacha_s2_balance_versions where active;
  v_snapshot_source := pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure);
  if (v_config->'directSupportItems'->'raceChangeSelector'->>'price')::integer <> 20000000
    or v_config->'supportItems'->'raceChangeSelector'->>'name' <> '종족선택 변경권'
    or v_snapshot_source not like '%c.race_override%'
    or to_regprocedure('public.gacha_s2_purchase_fixed_support_item(uuid,bigint,text,text)') is null
    or exists (
      select 1 from public.gacha_s2_player_states
      where support_items ? 'raceChangeSelector'
        and coalesce((support_items->>'raceChangeSelector')::integer, 0) <= 0
    ) then
    raise exception 'race change selector safe re-enable verification failed';
  end if;
end;
$verify$;

commit;
