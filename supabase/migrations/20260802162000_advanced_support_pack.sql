-- Align rare labels with the displayed odds and add a server-authoritative
-- advanced support pack. Random trait tickets remain outside guarantee tables.

begin;

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

  v_config := jsonb_set(
    v_config,
    '{supportPack,rareItems}',
    '["destructionGuard","premiumTicket","adventureRunReset","quickBattleReset","traitReroll"]'::jsonb,
    true
  );
  v_config := jsonb_set(
    v_config,
    '{supportPack,guaranteeRates}',
    '{"destructionGuard":77,"premiumTicket":8,"adventureRunReset":4,"quickBattleReset":11}'::jsonb,
    true
  );
  v_config := jsonb_set(
    v_config,
    '{advancedSupportPack}',
    '{
      "name":"고급 작전 지원 보급팩",
      "price":1500,
      "tenPrice":15000,
      "items":{
        "energyLarge":12,
        "enhance10":18,
        "destructionGuard":15,
        "cardExpPotion":12,
        "exp2h":12,
        "eliteTicket":10,
        "raceTicket":8,
        "premiumTicket":6,
        "adventureRunReset":3,
        "quickBattleReset":3.99,
        "traitReroll":0.01
      },
      "rareItems":["destructionGuard","traitReroll"],
      "guaranteeRates":{"destructionGuard":100}
    }'::jsonb,
    true
  );

  select sum(value::numeric) into v_total from jsonb_each_text(v_config->'supportPack'->'items');
  if v_total <> 100 then raise exception 'standard support weights must total 100, got %', v_total; end if;
  select sum(value::numeric) into v_total from jsonb_each_text(v_config->'supportPack'->'guaranteeRates');
  if v_total <> 100 then raise exception 'standard guarantee weights must total 100, got %', v_total; end if;
  select sum(value::numeric) into v_total from jsonb_each_text(v_config->'advancedSupportPack'->'items');
  if v_total <> 100 then raise exception 'advanced support weights must total 100, got %', v_total; end if;
  select sum(value::numeric) into v_total from jsonb_each_text(v_config->'advancedSupportPack'->'guaranteeRates');
  if v_total <> 100 then raise exception 'advanced guarantee weights must total 100, got %', v_total; end if;
  if v_config->'supportPack'->'guaranteeRates' ? 'traitReroll'
    or v_config->'advancedSupportPack'->'guaranteeRates' ? 'traitReroll' then
    raise exception 'random trait ticket must stay outside guarantee tables';
  end if;

  update public.gacha_s2_balance_versions
  set config = v_config,
      config_hash = encode(digest(v_config::text, 'sha256'), 'hex')
  where active;
end;
$balance$;

create or replace function public.gacha_s2_purchase_advanced_support_pack(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_quantity integer
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
  v_pack jsonb;
  v_cost integer;
  v_seed bigint;
  v_index integer;
  v_item_id text;
  v_results jsonb := '[]'::jsonb;
  v_has_rare boolean := false;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_quantity not in (1, 10) then
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '고급 지원팩 구매 요청이 올바르지 않습니다.', greatest(coalesce(p_expected_revision, 0), 0), null, null);
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'purchaseAdvancedSupportPack', 'expectedRevision', p_expected_revision, 'quantity', p_quantity
  )::text, 'sha256'), 'hex');

  select revision, points into v_revision, v_points
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태가 없습니다.', 0, null, null); end if;
  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'purchaseAdvancedSupportPack' then
      return public.gacha_s2_command_error(p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '동일 요청 키를 재사용할 수 없습니다.', v_revision, null, null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key, 'VERSION_CONFLICT', '최신 상태를 다시 불러와야 합니다.', v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;

  select config into v_config from public.gacha_s2_balance_versions where active;
  v_pack := v_config->'advancedSupportPack';
  v_cost := case when p_quantity = 10 then (v_pack->>'tenPrice')::integer else (v_pack->>'price')::integer end;
  if v_pack is null or v_points < v_cost then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '포인트가 부족하거나 고급 지원팩 설정이 없습니다.', v_revision, null, null);
  end if;

  v_seed := public.gacha_s2_new_seed();
  for v_index in 0..(p_quantity - 1) loop
    if p_quantity = 10 and v_index = 9 and not v_has_rare then
      v_item_id := public.gacha_s2_weighted_json_pick(v_pack->'guaranteeRates', v_seed, v_index);
    else
      v_item_id := public.gacha_s2_weighted_json_pick(v_pack->'items', v_seed, v_index);
    end if;
    if v_item_id is null then raise exception 'advanced support pack weight table is empty'; end if;
    v_has_rare := v_has_rare or coalesce(v_pack->'rareItems' ? v_item_id, false);
    update public.gacha_s2_player_states
    set support_items = jsonb_set(
      support_items, array[v_item_id], to_jsonb(coalesce((support_items->>v_item_id)::integer, 0) + 1), true
    ) where user_id = p_user_id;
    insert into public.gacha_s2_support_draws (user_id, command_id, draw_index, item_id, server_seed)
    values (p_user_id, p_idempotency_key, v_index, v_item_id, v_seed);
    v_results := v_results || to_jsonb(v_item_id);
  end loop;

  update public.gacha_s2_player_states
  set points = points - v_cost, shop_transactions = shop_transactions + 1,
      revision = revision + 1, updated_at = now()
  where user_id = p_user_id returning revision into v_revision;
  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true, 'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', v_seed,
    'snapshot', v_snapshot, 'result', jsonb_build_object('quantity', p_quantity, 'spentPoints', v_cost, 'items', v_results)
  );
  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response, expires_at)
  values (p_user_id, p_idempotency_key, 'purchaseAdvancedSupportPack', v_request_hash, v_response, now() + interval '24 hours');
  insert into public.gacha_s2_command_audit (user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed)
  values (p_user_id, p_idempotency_key, 'purchaseAdvancedSupportPack', v_request_hash, p_expected_revision, v_revision, v_seed);
  return v_response;
end;
$$;

revoke all on function public.gacha_s2_purchase_advanced_support_pack(uuid, bigint, text, integer) from public, anon, authenticated;
grant execute on function public.gacha_s2_purchase_advanced_support_pack(uuid, bigint, text, integer) to service_role;

do $verify$
declare
  v_config jsonb;
begin
  select config into v_config from public.gacha_s2_balance_versions where active;
  if (v_config->'advancedSupportPack'->>'price')::integer <> 1500
    or (v_config->'advancedSupportPack'->>'tenPrice')::integer <> 15000
    or (v_config->'advancedSupportPack'->'items'->>'traitReroll')::numeric <> 0.01
    or to_regprocedure('public.gacha_s2_purchase_advanced_support_pack(uuid,bigint,text,integer)') is null then
    raise exception 'advanced support pack verification failed';
  end if;
end;
$verify$;

commit;
