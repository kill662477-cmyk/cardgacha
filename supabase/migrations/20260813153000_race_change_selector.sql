-- Fixed-price race selector: buy for 20,000,000P, then change one owned combat card's account race.

begin;

alter table public.gacha_s2_player_cards
  add column if not exists race_override text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'gacha_s2_player_cards_race_override_check'
      and conrelid = 'public.gacha_s2_player_cards'::regclass
  ) then
    alter table public.gacha_s2_player_cards
      add constraint gacha_s2_player_cards_race_override_check
      check (race_override is null or race_override in ('저그','테란','프로토스'));
  end if;
end;
$$;

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

update public.gacha_s2_player_states
set support_items = jsonb_set(
  support_items,
  '{raceChangeSelector}',
  to_jsonb(coalesce((support_items->>'raceChangeSelector')::integer, 0)),
  true
);

create or replace function public.gacha_s2_purchase_fixed_support_item(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_item_id text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_points integer;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_config jsonb;
  v_product jsonb;
  v_price integer;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_item_id <> 'raceChangeSelector' then
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '고정가 아이템 구매 요청이 올바르지 않습니다.', greatest(coalesce(p_expected_revision, 0), 0), null, null);
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'purchaseFixedSupportItem', 'expectedRevision', p_expected_revision, 'itemId', p_item_id
  )::text, 'sha256'), 'hex');

  select revision, points into v_revision, v_points
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태가 없습니다.', 0, null, null); end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'purchaseFixedSupportItem' then
      return public.gacha_s2_command_error(p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '동일 요청 키를 재사용할 수 없습니다.', v_revision, null, null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key, 'VERSION_CONFLICT', '최신 상태를 다시 불러와야 합니다.', v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;

  select config into v_config from public.gacha_s2_balance_versions where active;
  v_product := v_config->'directSupportItems'->p_item_id;
  v_price := coalesce((v_product->>'price')::integer, 0);
  if v_product is null or v_price <> 20000000 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '판매 설정을 불러오지 못했습니다.', v_revision, null, null);
  end if;
  if v_points < v_price then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '포인트가 부족합니다.', v_revision, null, null);
  end if;

  update public.gacha_s2_player_states
  set points = points - v_price,
      support_items = jsonb_set(
        support_items, array[p_item_id], to_jsonb(coalesce((support_items->>p_item_id)::integer, 0) + 1), true
      ),
      shop_transactions = shop_transactions + 1,
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id
  returning revision into v_revision;

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true, 'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', null,
    'snapshot', v_snapshot,
    'result', jsonb_build_object('itemId', p_item_id, 'quantity', 1, 'spentPoints', v_price)
  );
  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response, expires_at)
  values (p_user_id, p_idempotency_key, 'purchaseFixedSupportItem', v_request_hash, v_response, now() + interval '24 hours');
  insert into public.gacha_s2_command_audit (user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed)
  values (p_user_id, p_idempotency_key, 'purchaseFixedSupportItem', v_request_hash, p_expected_revision, v_revision, null);
  return v_response;
end;
$$;

revoke all on function public.gacha_s2_purchase_fixed_support_item(uuid, bigint, text, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_purchase_fixed_support_item(uuid, bigint, text, text) to service_role;

-- Include the account race in normal snapshots so all client battle/synergy paths use it.
do $snapshot_patch$
declare
  v_def text;
  v_next text;
  v_source text := '''archetype'', coalesce(c.archetype_override, (select catalog.archetype from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id))';
begin
  select pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure) into v_def;
  v_next := replace(
    v_def,
    v_source,
    v_source || ', ''race'', coalesce(c.race_override, (select catalog.race from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id))'
  );
  if v_next = v_def or strpos(v_next, '''race'', coalesce(c.race_override') = 0 then
    raise exception 'player snapshot race patch source mismatch';
  end if;
  execute v_next;
end;
$snapshot_patch$;

-- Add the selectable race branch to the existing support-item RPC.
do $item_rpc_patch$
declare
  v_def text;
  v_next text;
  v_trait_branch text := '  elsif coalesce((v_item->>''traitReroll'')::boolean, false) then';
begin
  select pg_get_functiondef(
    'public.gacha_s2_use_support_item(uuid,bigint,text,text,text,text,integer)'::regprocedure
  ) into v_def;

  v_next := replace(
    v_def,
    '  v_archetype text;',
    E'  v_archetype text;\n  v_previous_race text;\n  v_race text;'
  );
  v_next := replace(
    v_next,
    v_trait_branch,
    E'  elsif coalesce((v_item->>''raceSelector'')::boolean, false) then\n'
    || E'    if p_race not in (''저그'',''테란'',''프로토스'') then\n'
    || E'      return public.gacha_s2_command_error(p_idempotency_key, ''VALIDATION_FAILED'', ''변경할 종족을 선택해 주세요.'', v_revision, null, null);\n'
    || E'    end if;\n'
    || E'    select coalesce(owned.race_override, catalog.race)\n'
    || E'    into v_previous_race\n'
    || E'    from public.gacha_s2_player_cards owned\n'
    || E'    join public.gacha_s2_card_catalog catalog on catalog.card_id = owned.card_id\n'
    || E'    where owned.user_id = p_user_id and owned.card_id = p_target_card_id\n'
    || E'      and owned.copies > 0 and catalog.rarity <> ''EX'' and not catalog.is_group\n'
    || E'    for update of owned;\n'
    || E'    if not found then\n'
    || E'      return public.gacha_s2_command_error(p_idempotency_key, ''COMMAND_REJECTED'', ''보유 중인 전투 카드만 변경할 수 있습니다.'', v_revision, null, null);\n'
    || E'    end if;\n'
    || E'    if p_race = v_previous_race then\n'
    || E'      return public.gacha_s2_command_error(p_idempotency_key, ''COMMAND_REJECTED'', ''현재 종족과 다른 종족을 선택해 주세요.'', v_revision, null, null);\n'
    || E'    end if;\n'
    || E'    v_race := p_race;\n'
    || E'    update public.gacha_s2_player_cards\n'
    || E'    set race_override = v_race, updated_at = now()\n'
    || E'    where user_id = p_user_id and card_id = p_target_card_id;\n'
    || E'    v_result := jsonb_build_object(''itemId'', p_item_id, ''cardId'', p_target_card_id, ''previousRace'', v_previous_race, ''race'', v_race);\n'
    || v_trait_branch
  );

  if v_next = v_def
    or strpos(v_next, 'v_previous_race text') = 0
    or strpos(v_next, 'race_override = v_race') = 0 then
    raise exception 'support item race patch source mismatch';
  end if;
  execute v_next;
end;
$item_rpc_patch$;

-- Profiles and deck viewers must expose the account race override too.
do $profile_patch$
declare
  v_signature text;
  v_def text;
  v_next text;
  v_source text := '''archetype'', coalesce(pc.archetype_override, (select catalog.archetype from public.gacha_s2_card_catalog catalog where catalog.card_id = pc.card_id))';
begin
  foreach v_signature in array array[
    'public.gacha_s2_get_guild_applicant_profile(uuid,uuid)',
    'public.gacha_s2_get_guild_member_profile(uuid,uuid)',
    'public.gacha_s2_get_power_ranking(uuid,integer)'
  ] loop
    execute format('select pg_get_functiondef(%L::regprocedure)', v_signature) into v_def;
    v_next := replace(
      v_def,
      v_source,
      v_source || ', ''race'', coalesce(pc.race_override, (select catalog.race from public.gacha_s2_card_catalog catalog where catalog.card_id = pc.card_id))'
    );
    if v_next = v_def or strpos(v_next, '''race'', coalesce(pc.race_override') = 0 then
      raise exception 'profile race patch source mismatch: %', v_signature;
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
  if (v_config->'directSupportItems'->'raceChangeSelector'->>'price')::integer <> 20000000
    or v_config->'supportItems'->'raceChangeSelector'->>'name' <> '종족선택 변경권'
    or to_regprocedure('public.gacha_s2_purchase_fixed_support_item(uuid,bigint,text,text)') is null then
    raise exception 'race change selector verification failed';
  end if;
end;
$verify$;

commit;
