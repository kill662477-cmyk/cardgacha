-- Add an account-scoped random trait reroll ticket to the support pack.
-- The 0.001% ticket is intentionally excluded from the 10-draw rare guarantee.

begin;

alter table public.gacha_s2_player_cards
  add column if not exists archetype_override text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'gacha_s2_player_cards_archetype_override_check'
      and conrelid = 'public.gacha_s2_player_cards'::regclass
  ) then
    alter table public.gacha_s2_player_cards
      add constraint gacha_s2_player_cards_archetype_override_check
      check (archetype_override is null or archetype_override in (
        'quick','heavy','combo','area','boss','amplify','weaken','sustain'
      ));
  end if;
end;
$$;

do $balance$
declare
  v_config jsonb;
  v_total numeric;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active
  for update;

  if v_config is null then raise exception 'active balance config missing'; end if;

  v_config := jsonb_set(v_config, '{supportPack,items,cardExpPotion}', '9.999'::jsonb, true);
  v_config := jsonb_set(v_config, '{supportPack,items,traitReroll}', '0.001'::jsonb, true);
  v_config := jsonb_set(
    v_config,
    '{supportItems,traitReroll}',
    '{"name":"랜덤특성변경권","category":"특성","effect":"선택 카드의 현재 특성을 제외한 다른 특성으로 무작위 변경","traitReroll":true,"ultraRare":true,"hideWhenEmpty":true}'::jsonb,
    true
  );

  select sum(value::numeric) into v_total
  from jsonb_each_text(v_config->'supportPack'->'items');
  if v_total <> 100 then raise exception 'support pack weight total must be 100, got %', v_total; end if;
  if v_config->'supportPack'->'rareItems' ? 'traitReroll'
    or v_config->'supportPack'->'guaranteeRates' ? 'traitReroll' then
    raise exception 'trait reroll must not be included in 10-draw guarantee';
  end if;

  update public.gacha_s2_balance_versions
  set config = v_config,
      config_hash = encode(digest(v_config::text, 'sha256'), 'hex')
  where active;
end;
$balance$;

update public.gacha_s2_player_states
set support_items = jsonb_set(
  support_items,
  '{traitReroll}',
  to_jsonb(coalesce((support_items->>'traitReroll')::integer, 0)),
  true
);

-- Add effective account trait to existing cardProgress. Old clients already spread
-- cardProgress over catalog cards, so open sessions remain compatible.
do $snapshot_patch$
declare
  v_def text;
  v_next text;
begin
  select pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure) into v_def;
  v_next := replace(
    v_def,
    'jsonb_build_object(''enhancement'', c.enhancement, ''exp'', c.card_exp)',
    'jsonb_build_object(''enhancement'', c.enhancement, ''exp'', c.card_exp, ''archetype'', coalesce(c.archetype_override, (select catalog.archetype from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id)))'
  );
  if v_next = v_def or strpos(v_next, '''archetype'', coalesce(c.archetype_override') = 0 then
    raise exception 'player snapshot trait patch source mismatch';
  end if;
  execute v_next;
end;
$snapshot_patch$;

-- Extend current seven-argument item RPC without disturbing its battle-tested
-- energy, potion, reset, and pack branches.
do $item_rpc_patch$
declare
  v_def text;
  v_next text;
begin
  select pg_get_functiondef(
    'public.gacha_s2_use_support_item(uuid,bigint,text,text,text,text,integer)'::regprocedure
  ) into v_def;

  v_next := replace(
    v_def,
    '  v_current_exp integer;',
    E'  v_current_exp integer;\n  v_previous_archetype text;\n  v_archetype text;\n  v_archetypes text[] := array[''quick'',''heavy'',''combo'',''area'',''boss'',''amplify'',''weaken'',''sustain''];'
  );
  v_next := replace(
    v_next,
    '  elsif v_item ? ''cardExp'' then',
    E'  elsif coalesce((v_item->>''traitReroll'')::boolean, false) then\n'
    || E'    select coalesce(owned.archetype_override, catalog.archetype)\n'
    || E'    into v_previous_archetype\n'
    || E'    from public.gacha_s2_player_cards owned\n'
    || E'    join public.gacha_s2_card_catalog catalog on catalog.card_id = owned.card_id\n'
    || E'    where owned.user_id = p_user_id and owned.card_id = p_target_card_id\n'
    || E'      and owned.copies > 0 and catalog.rarity <> ''EX'' and not catalog.is_group\n'
    || E'    for update of owned;\n'
    || E'    if not found then\n'
    || E'      return public.gacha_s2_command_error(p_idempotency_key, ''COMMAND_REJECTED'', ''보유 중인 전투 카드만 변경할 수 있습니다.'', v_revision, null, null);\n'
    || E'    end if;\n'
    || E'    v_seed := public.gacha_s2_new_seed();\n'
    || E'    v_archetypes := array_remove(v_archetypes, v_previous_archetype);\n'
    || E'    v_archetype := v_archetypes[least(array_length(v_archetypes, 1), floor(public.gacha_s2_seed_roll(v_seed, 0) * array_length(v_archetypes, 1))::integer + 1)];\n'
    || E'    update public.gacha_s2_player_cards\n'
    || E'    set archetype_override = v_archetype, updated_at = now()\n'
    || E'    where user_id = p_user_id and card_id = p_target_card_id;\n'
    || E'    v_result := jsonb_build_object(''itemId'', p_item_id, ''cardId'', p_target_card_id, ''previousArchetype'', v_previous_archetype, ''archetype'', v_archetype);\n'
    || E'  elsif v_item ? ''cardExp'' then'
  );

  if v_next = v_def
    or strpos(v_next, 'v_previous_archetype text') = 0
    or strpos(v_next, 'archetype_override = v_archetype') = 0 then
    raise exception 'support item trait patch source mismatch';
  end if;
  execute v_next;
end;
$item_rpc_patch$;

-- Deck viewers need the account override, not the catalog default.
do $profile_patch$
declare
  v_signature text;
  v_def text;
  v_next text;
begin
  foreach v_signature in array array[
    'public.gacha_s2_get_guild_applicant_profile(uuid,uuid)',
    'public.gacha_s2_get_guild_member_profile(uuid,uuid)',
    'public.gacha_s2_get_power_ranking(uuid,integer)'
  ] loop
    execute format('select pg_get_functiondef(%L::regprocedure)', v_signature) into v_def;
    v_next := replace(
      v_def,
      '''enhancement'', coalesce(pc.enhancement, 0)',
      '''enhancement'', coalesce(pc.enhancement, 0), ''archetype'', coalesce(pc.archetype_override, (select catalog.archetype from public.gacha_s2_card_catalog catalog where catalog.card_id = pc.card_id))'
    );
    if v_next = v_def or strpos(v_next, '''archetype'', coalesce(pc.archetype_override') = 0 then
      raise exception 'profile trait patch source mismatch: %', v_signature;
    end if;
    execute v_next;
  end loop;
end;
$profile_patch$;

do $verify$
declare
  v_config jsonb;
begin
  select config into v_config from public.gacha_s2_balance_versions where active;
  if (v_config->'supportPack'->'items'->>'traitReroll')::numeric <> 0.001
    or (v_config->'supportPack'->'items'->>'cardExpPotion')::numeric <> 9.999
    or v_config->'supportItems'->'traitReroll'->>'name' <> '랜덤특성변경권' then
    raise exception 'random trait reroll config verification failed';
  end if;
end;
$verify$;

commit;
