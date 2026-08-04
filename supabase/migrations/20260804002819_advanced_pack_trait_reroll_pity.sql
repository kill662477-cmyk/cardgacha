-- 고급 작전 지원 보급팩 누적 구매액 확정 지급.
-- 고급팩에 쓴 포인트가 advancedSupportPack.guaranteedTraitRerollPoints(300만) 를 넘을 때마다
-- 랜덤특성변경권(traitReroll) 1장을 지급하고 누적액에서 그만큼 차감한다.
-- 일반 보급팩은 대상이 아니다.
--
-- 운영 요청에 따라 지급을 별도로 알리지 않는다: 뽑기 결과 목록(result.items)에 넣지 않고
-- 인벤토리에만 반영한다. 추적은 아래 누적 테이블로만 한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(
      config,
      '{advancedSupportPack,guaranteedTraitRerollPoints}',
      '3000000'::jsonb,
      true
    )
where active;

create table if not exists public.gacha_s2_advanced_pack_trait_pity (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  -- 마지막 확정 지급 이후 고급팩에 쓴 누적 포인트.
  spent_since_grant bigint not null default 0 check (spent_since_grant >= 0),
  -- 지금까지 확정 지급으로 나간 장수.
  granted_count integer not null default 0 check (granted_count >= 0),
  -- 고급팩에 쓴 전체 누적 포인트(차감하지 않는다).
  lifetime_spent bigint not null default 0 check (lifetime_spent >= 0),
  updated_at timestamptz not null default now()
);

alter table public.gacha_s2_advanced_pack_trait_pity enable row level security;
revoke all on table public.gacha_s2_advanced_pack_trait_pity from public, anon, authenticated;

create or replace function public.gacha_s2_purchase_advanced_support_pack(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_quantity integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
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
  v_pity_threshold bigint;
  v_pity_spent bigint;
  v_pity_grants integer := 0;
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

  -- 누적 구매액 확정 지급. 임계값이 없거나 0 이하면 이 구간은 통째로 건너뛴다.
  v_pity_threshold := coalesce((v_pack->>'guaranteedTraitRerollPoints')::bigint, 0);
  if v_pity_threshold > 0 then
    insert into public.gacha_s2_advanced_pack_trait_pity (user_id, spent_since_grant, lifetime_spent, updated_at)
    values (p_user_id, v_cost, v_cost, now())
    on conflict (user_id) do update
    set spent_since_grant = public.gacha_s2_advanced_pack_trait_pity.spent_since_grant + excluded.spent_since_grant,
        lifetime_spent = public.gacha_s2_advanced_pack_trait_pity.lifetime_spent + excluded.lifetime_spent,
        updated_at = now()
    returning spent_since_grant into v_pity_spent;

    v_pity_grants := (v_pity_spent / v_pity_threshold)::integer;
    if v_pity_grants > 0 then
      update public.gacha_s2_advanced_pack_trait_pity
      set spent_since_grant = spent_since_grant - (v_pity_grants::bigint * v_pity_threshold),
          granted_count = granted_count + v_pity_grants,
          updated_at = now()
      where user_id = p_user_id;

      -- 인벤토리에만 반영한다. v_results 에 넣지 않으므로 뽑기 결과창에는 나오지 않는다.
      update public.gacha_s2_player_states
      set support_items = jsonb_set(
        support_items, array['traitReroll'],
        to_jsonb(coalesce((support_items->>'traitReroll')::integer, 0) + v_pity_grants), true
      ) where user_id = p_user_id;
    end if;
  end if;

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
$function$;

revoke all on function public.gacha_s2_purchase_advanced_support_pack(uuid, bigint, text, integer)
from public, anon, authenticated;
grant execute on function public.gacha_s2_purchase_advanced_support_pack(uuid, bigint, text, integer)
to service_role;

do $$
declare v_threshold bigint;
begin
  select (config->'advancedSupportPack'->>'guaranteedTraitRerollPoints')::bigint into v_threshold
  from public.gacha_s2_balance_versions where active;
  if v_threshold is distinct from 3000000 then
    raise exception 'advanced pack pity threshold not applied: %', v_threshold;
  end if;
  if pg_get_functiondef(
       'public.gacha_s2_purchase_advanced_support_pack(uuid,bigint,text,integer)'::regprocedure
     ) not like '%gacha_s2_advanced_pack_trait_pity%' then
    raise exception 'advanced pack pity logic missing from RPC';
  end if;
end;
$$;
