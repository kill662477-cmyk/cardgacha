-- Card Gacha Season 2: remaining atomic economy and profile commands.
-- REVIEW ONLY. Run after migrations 001-006. Service role only.

begin;

do $$
begin
  if to_regprocedure('public.gacha_s2_get_player_snapshot(uuid)') is null
    or to_regprocedure('public.gacha_s2_new_seed()') is null
    or to_regprocedure('public.gacha_s2_grant_formation_exp(uuid,jsonb,integer,jsonb)') is null then
    raise exception 'missing Season 2 command schema: run migrations 001-006 first';
  end if;
end;
$$;

create table if not exists public.gacha_s2_support_draws (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  command_id text not null,
  draw_index integer not null check (draw_index >= 0),
  item_id text not null,
  server_seed bigint not null check (server_seed between 0 and 4294967295),
  created_at timestamptz not null default now(),
  unique (user_id, command_id, draw_index)
);

create index if not exists idx_gacha_s2_support_draws_user_created
  on public.gacha_s2_support_draws(user_id, created_at desc);
alter table public.gacha_s2_support_draws enable row level security;

create or replace function public.gacha_s2_weighted_json_pick(
  p_weights jsonb,
  p_seed bigint,
  p_counter integer
) returns text
language sql
immutable
strict
as $$
  with weights as (
    select key as item_id, value::numeric as weight
    from jsonb_each_text(p_weights)
    where value::numeric > 0
  ), weighted as (
    select item_id,
      sum(weight) over (order by item_id) as cumulative,
      sum(weight) over () as total
    from weights
  )
  select item_id
  from weighted
  where public.gacha_s2_seed_roll(p_seed, p_counter) * total < cumulative
  order by cumulative
  limit 1;
$$;

create or replace function public.gacha_s2_draw_pack_for_command(
  p_user_id uuid,
  p_command_id text,
  p_product_id text,
  p_race text,
  p_seed bigint,
  p_counter_offset integer default 0
) returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_config jsonb;
  v_pack jsonb;
  v_count integer;
  v_index integer;
  v_roll numeric;
  v_rarity text;
  v_candidate_count integer;
  v_card_id text;
  v_results jsonb := '[]'::jsonb;
begin
  if p_product_id not in ('general','elite','premium','race')
    or (p_product_id = 'race' and p_race not in ('저그','테란','프로토스'))
    or (p_product_id <> 'race' and p_race is not null) then
    raise exception 'invalid card pack request';
  end if;
  select config into v_config from public.gacha_s2_balance_versions where active;
  v_pack := v_config->'packs'->p_product_id;
  v_count := (v_pack->>'count')::integer;
  if v_pack is null or v_count < 1 then raise exception 'active card pack missing'; end if;

  for v_index in 0..(v_count - 1) loop
    v_roll := public.gacha_s2_seed_roll(p_seed, p_counter_offset + v_index * 2);
    with rates as (
      select key as rarity, value::numeric as weight,
        case key when 'F' then 1 when 'E' then 2 when 'D' then 3 when 'C' then 4
          when 'B' then 5 when 'A' then 6 when 'S' then 7 when 'SS' then 8 when 'SSS' then 9 end as rarity_order
      from jsonb_each_text(v_pack->'rates')
    ), weighted as (
      select rarity,
        sum(weight) over (order by rarity_order) as cumulative,
        sum(weight) over () as total
      from rates
    )
    select rarity into v_rarity
    from weighted
    where v_roll * total < cumulative
    order by cumulative
    limit 1;

    select count(*) into v_candidate_count
    from public.gacha_s2_card_catalog
    where rarity = v_rarity and not is_group
      and (p_product_id <> 'race' or race = p_race);
    if v_candidate_count < 1 then raise exception 'no eligible card for rarity %', v_rarity; end if;

    select card_id into v_card_id
    from public.gacha_s2_card_catalog
    where rarity = v_rarity and not is_group
      and (p_product_id <> 'race' or race = p_race)
    order by card_id
    offset floor(public.gacha_s2_seed_roll(p_seed, p_counter_offset + v_index * 2 + 1) * v_candidate_count)::integer
    limit 1;

    insert into public.gacha_s2_player_cards (user_id, card_id, copies)
    values (p_user_id, v_card_id, 1)
    on conflict (user_id, card_id) do update
      set copies = public.gacha_s2_player_cards.copies + 1, updated_at = now();
    insert into public.gacha_s2_collection_records (user_id, card_id)
    values (p_user_id, v_card_id) on conflict (user_id, card_id) do nothing;
    insert into public.gacha_s2_pack_draws (
      user_id, command_id, draw_index, product_id, race, card_id, rarity, server_seed
    ) values (
      p_user_id, p_command_id, v_index, p_product_id, p_race, v_card_id, v_rarity, p_seed
    );
    v_results := v_results || jsonb_build_array(jsonb_build_object('cardId', v_card_id, 'rarity', v_rarity));
  end loop;
  return v_results;
end;
$$;

create or replace function public.gacha_s2_purchase_support_pack(
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
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '지원팩 구매 요청이 올바르지 않습니다.', greatest(coalesce(p_expected_revision, 0), 0), null, null);
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'purchaseSupportPack', 'expectedRevision', p_expected_revision, 'quantity', p_quantity
  )::text, 'sha256'), 'hex');

  select revision, points into v_revision, v_points
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태가 없습니다.', 0, null, null); end if;
  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'purchaseSupportPack' then
      return public.gacha_s2_command_error(p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '동일 요청 키를 재사용할 수 없습니다.', v_revision, null, null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key, 'VERSION_CONFLICT', '최신 상태를 다시 불러와야 합니다.', v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;

  select config into v_config from public.gacha_s2_balance_versions where active;
  v_pack := v_config->'supportPack';
  v_cost := case when p_quantity = 10 then (v_pack->>'tenPrice')::integer else (v_pack->>'price')::integer end;
  if v_pack is null or v_points < v_cost then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '포인트가 부족하거나 지원팩 설정이 없습니다.', v_revision, null, null);
  end if;

  v_seed := public.gacha_s2_new_seed();
  for v_index in 0..(p_quantity - 1) loop
    if p_quantity = 10 and v_index = 9 and not v_has_rare then
      v_item_id := public.gacha_s2_weighted_json_pick(v_pack->'guaranteeRates', v_seed, v_index);
    else
      v_item_id := public.gacha_s2_weighted_json_pick(v_pack->'items', v_seed, v_index);
    end if;
    if v_item_id is null then raise exception 'support pack weight table is empty'; end if;
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
  values (p_user_id, p_idempotency_key, 'purchaseSupportPack', v_request_hash, v_response, now() + interval '24 hours');
  insert into public.gacha_s2_command_audit (user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed)
  values (p_user_id, p_idempotency_key, 'purchaseSupportPack', v_request_hash, p_expected_revision, v_revision, v_seed);
  return v_response;
end;
$$;

create or replace function public.gacha_s2_use_support_item(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_item_id text,
  p_target_card_id text default null,
  p_race text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_config jsonb;
  v_item jsonb;
  v_items jsonb;
  v_buffs jsonb;
  v_energy integer;
  v_max_energy integer;
  v_last_energy timestamptz;
  v_quick jsonb;
  v_runs jsonb;
  v_seed bigint := 0;
  v_result jsonb := '{}'::jsonb;
  v_cards jsonb;
  v_required integer;
  v_current_exp integer;
  v_gained integer;
  v_now_ms bigint := public.gacha_s2_now_ms();
  v_end_ms bigint;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_item_id is null or length(p_item_id) > 80 then
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '아이템 사용 요청이 올바르지 않습니다.', greatest(coalesce(p_expected_revision, 0), 0), null, null);
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'useSupportItem', 'expectedRevision', p_expected_revision,
    'itemId', p_item_id, 'targetCardId', p_target_card_id, 'race', p_race
  )::text, 'sha256'), 'hex');

  select revision, support_items, active_buffs, action_energy, max_action_energy, last_energy_at, quick_battle, adventure_runs
  into v_revision, v_items, v_buffs, v_energy, v_max_energy, v_last_energy, v_quick, v_runs
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태가 없습니다.', 0, null, null); end if;
  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'useSupportItem' then
      return public.gacha_s2_command_error(p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '동일 요청 키를 재사용할 수 없습니다.', v_revision, null, null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key, 'VERSION_CONFLICT', '최신 상태를 다시 불러와야 합니다.', v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;

  select config into v_config from public.gacha_s2_balance_versions where active;
  v_item := v_config->'supportItems'->p_item_id;
  if v_item is null or coalesce((v_items->>p_item_id)::integer, 0) < 1 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '보유하지 않은 아이템입니다.', v_revision, null, null);
  end if;

  if v_item ? 'energy' then
    if v_energy >= v_max_energy * 2 then
      return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '행동력 충전 상한입니다.', v_revision, null, null);
    end if;
    if v_energy < v_max_energy then
      v_energy := least(v_max_energy, v_energy + floor(extract(epoch from (now() - v_last_energy)) / 60 / (v_config->'rewardRules'->>'energyRecoveryMinutes')::numeric)::integer);
    end if;
    v_energy := least(v_max_energy * 2, v_energy + (v_item->>'energy')::integer);
    update public.gacha_s2_player_states set action_energy = v_energy, last_energy_at = now() where user_id = p_user_id;
    v_result := jsonb_build_object('itemId', p_item_id, 'actionEnergy', v_energy);
  elsif v_item ? 'durationMinutes' then
    v_end_ms := greatest(v_now_ms, coalesce((v_buffs->>'cardExpEndAt')::bigint, 0));
    v_buffs := jsonb_set(v_buffs, '{cardExpStartAt}', to_jsonb(case when v_end_ms > v_now_ms then coalesce((v_buffs->>'cardExpStartAt')::bigint, v_now_ms) else v_now_ms end), true);
    v_buffs := jsonb_set(v_buffs, '{cardExpEndAt}', to_jsonb(v_end_ms + (v_item->>'durationMinutes')::bigint * 60000), true);
    update public.gacha_s2_player_states set active_buffs = v_buffs where user_id = p_user_id;
    v_result := jsonb_build_object('itemId', p_item_id, 'activeBuffs', v_buffs);
  elsif v_item->>'reset' = 'adventureRuns' then
    if coalesce((v_runs->>'count')::integer, 0) < 1 then
      return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '초기화할 모험 시작 횟수가 없습니다.', v_revision, null, null);
    end if;
    update public.gacha_s2_player_states set adventure_runs = '{"windowStartedAt":0,"count":0}'::jsonb where user_id = p_user_id;
    v_result := jsonb_build_object('itemId', p_item_id, 'adventureRuns', jsonb_build_object('windowStartedAt', 0, 'count', 0));
  elsif v_item->>'reset' = 'quickBattle' then
    if v_quick->>'date' <> to_char(timezone('Asia/Seoul', now()), 'YYYY-MM-DD') or coalesce((v_quick->>'count')::integer, 0) < 1 then
      return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '초기화할 빠른 전투 횟수가 없습니다.', v_revision, null, null);
    end if;
    v_quick := jsonb_set(v_quick, '{count}', '0'::jsonb, true);
    update public.gacha_s2_player_states set quick_battle = v_quick where user_id = p_user_id;
    v_result := jsonb_build_object('itemId', p_item_id, 'quickBattle', v_quick);
  elsif v_item ? 'cardExp' then
    select (v_config->'enhancement'->'expRequirements'->>owned.enhancement)::integer, owned.card_exp
    into v_required, v_current_exp
    from public.gacha_s2_player_cards owned
    join public.gacha_s2_card_catalog catalog on catalog.card_id = owned.card_id
    where owned.user_id = p_user_id and owned.card_id = p_target_card_id and catalog.rarity <> 'EX'
    for update of owned;
    if not found or v_required <= 0 or v_current_exp >= v_required then
      return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '카드 EXP를 올릴 수 없습니다.', v_revision, null, null);
    end if;
    v_gained := least((v_item->>'cardExp')::integer, v_required - v_current_exp);
    update public.gacha_s2_player_cards set card_exp = card_exp + v_gained, updated_at = now()
    where user_id = p_user_id and card_id = p_target_card_id;
    v_result := jsonb_build_object('itemId', p_item_id, 'cardId', p_target_card_id, 'cardExpGained', v_gained);
  elsif v_item ? 'pack' then
    if v_item->>'pack' = 'race' and p_race not in ('저그','테란','프로토스') then
      return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '종족 선택이 필요합니다.', v_revision, null, null);
    elsif v_item->>'pack' <> 'race' and p_race is not null then
      return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '이 교환권에는 종족을 지정할 수 없습니다.', v_revision, null, null);
    end if;
    v_seed := public.gacha_s2_new_seed();
    v_cards := public.gacha_s2_draw_pack_for_command(p_user_id, p_idempotency_key, v_item->>'pack', p_race, v_seed, 0);
    v_result := jsonb_build_object('itemId', p_item_id, 'productId', v_item->>'pack', 'race', p_race, 'cards', v_cards);
  else
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '이 아이템은 해당 화면에서 사용할 수 없습니다.', v_revision, null, null);
  end if;

  update public.gacha_s2_player_states
  set support_items = jsonb_set(support_items, array[p_item_id], to_jsonb((support_items->>p_item_id)::integer - 1), true),
      revision = revision + 1, updated_at = now()
  where user_id = p_user_id returning revision into v_revision;
  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true, 'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', v_seed,
    'snapshot', v_snapshot, 'result', v_result
  );
  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response, expires_at)
  values (p_user_id, p_idempotency_key, 'useSupportItem', v_request_hash, v_response, now() + interval '24 hours');
  insert into public.gacha_s2_command_audit (user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed)
  values (p_user_id, p_idempotency_key, 'useSupportItem', v_request_hash, p_expected_revision, v_revision, nullif(v_seed, 0));
  return v_response;
end;
$$;

create or replace function public.gacha_s2_claim_idle_reward(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_idle_bonus numeric
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_last_reward timestamptz;
  v_stage integer;
  v_buffs jsonb;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_config jsonb;
  v_formation jsonb;
  v_elapsed_seconds bigint;
  v_boosted_seconds bigint;
  v_from_ms bigint;
  v_to_ms bigint := public.gacha_s2_now_ms();
  v_rate numeric;
  v_card_exp integer;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_idle_bonus is null or p_idle_bonus < 0 or p_idle_bonus > 1 then
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '방치 보상 요청이 올바르지 않습니다.', greatest(coalesce(p_expected_revision, 0), 0), null, null);
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'claimAdventureRewards', 'mode', 'offline', 'expectedRevision', p_expected_revision,
    'idleBonus', round(p_idle_bonus, 8)
  )::text, 'sha256'), 'hex');

  select revision, last_reward_at, cleared_stage, active_buffs
  into v_revision, v_last_reward, v_stage, v_buffs
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태가 없습니다.', 0, null, null); end if;
  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'claimAdventureRewards' then
      return public.gacha_s2_command_error(p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '동일 요청 키를 재사용할 수 없습니다.', v_revision, null, null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key, 'VERSION_CONFLICT', '최신 상태를 다시 불러와야 합니다.', v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;

  select config into v_config from public.gacha_s2_balance_versions where active;
  v_formation := public.gacha_s2_formation_snapshot(p_user_id);
  if v_formation is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '전투 편성 5장을 먼저 설정해야 합니다.', v_revision, null, null);
  end if;
  v_elapsed_seconds := least(
    floor(extract(epoch from greatest(now() - v_last_reward, interval '0 seconds')))::bigint,
    (v_config->'rewardRules'->>'offlineCapHours')::bigint * 3600
  );
  v_from_ms := floor(extract(epoch from v_last_reward) * 1000)::bigint;
  v_boosted_seconds := greatest(0, least(
    v_elapsed_seconds,
    (least(v_to_ms, coalesce((v_buffs->>'cardExpEndAt')::bigint, 0))
      - greatest(v_from_ms, coalesce((v_buffs->>'cardExpStartAt')::bigint, 0))) / 1000
  ));
  v_rate := (v_config->'rewardRules'->>'cardExpBasePerMinute')::numeric
    + greatest(1, least((v_config->'rewardRules'->>'maxStage')::integer, v_stage))
      * (v_config->'rewardRules'->>'cardExpPerStage')::numeric;
  v_card_exp := floor(v_rate * v_elapsed_seconds / 60 * (1 + p_idle_bonus))::integer
    + case when v_boosted_seconds > 0
      then greatest(1, floor(v_rate * v_boosted_seconds / 60 * 0.5 * (1 + p_idle_bonus))::integer)
      else 0 end;
  perform public.gacha_s2_grant_formation_exp(p_user_id, v_formation, v_card_exp, v_config);

  update public.gacha_s2_player_states
  set last_reward_at = now(), revision = revision + 1, updated_at = now()
  where user_id = p_user_id returning revision into v_revision;
  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true, 'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', 0,
    'snapshot', v_snapshot, 'result', jsonb_build_object(
      'mode', 'offline', 'elapsedSeconds', v_elapsed_seconds, 'boostedSeconds', v_boosted_seconds, 'cardExp', v_card_exp
    )
  );
  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response, expires_at)
  values (p_user_id, p_idempotency_key, 'claimAdventureRewards', v_request_hash, v_response, now() + interval '24 hours');
  insert into public.gacha_s2_command_audit (user_id, command_id, command_type, request_hash, expected_revision, committed_revision)
  values (p_user_id, p_idempotency_key, 'claimAdventureRewards', v_request_hash, p_expected_revision, v_revision);
  return v_response;
end;
$$;

create or replace function public.gacha_s2_set_representative_card(
  p_user_id uuid, p_expected_revision bigint, p_idempotency_key text, p_card_id text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_card_id is null or length(trim(p_card_id)) < 1 or length(p_card_id) > 80 then
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '대표 카드 요청이 올바르지 않습니다.', greatest(coalesce(p_expected_revision, 0), 0), null, null);
  end if;
  v_request_hash := encode(digest(jsonb_build_object('type', 'setRepresentativeCard', 'expectedRevision', p_expected_revision, 'cardId', p_card_id)::text, 'sha256'), 'hex');
  select revision into v_revision from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태가 없습니다.', 0, null, null); end if;
  select * into v_previous from public.gacha_s2_idempotency where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'setRepresentativeCard' then
      return public.gacha_s2_command_error(p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '동일 요청 키를 재사용할 수 없습니다.', v_revision, null, null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key, 'VERSION_CONFLICT', '최신 상태를 다시 불러와야 합니다.', v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;
  if not exists (select 1 from public.gacha_s2_player_cards where user_id = p_user_id and card_id = p_card_id and copies > 0) then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '보유 카드만 대표 카드로 설정할 수 있습니다.', v_revision, null, null);
  end if;
  update public.gacha_s2_player_states set representative_card_id = p_card_id, revision = revision + 1, updated_at = now()
  where user_id = p_user_id returning revision into v_revision;
  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object('contractVersion', 1, 'ok', true, 'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', 0, 'snapshot', v_snapshot,
    'result', jsonb_build_object('cardId', p_card_id));
  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response, expires_at)
  values (p_user_id, p_idempotency_key, 'setRepresentativeCard', v_request_hash, v_response, now() + interval '24 hours');
  insert into public.gacha_s2_command_audit (user_id, command_id, command_type, request_hash, expected_revision, committed_revision)
  values (p_user_id, p_idempotency_key, 'setRepresentativeCard', v_request_hash, p_expected_revision, v_revision);
  return v_response;
end;
$$;

create or replace function public.gacha_s2_set_card_lock(
  p_user_id uuid, p_expected_revision bigint, p_idempotency_key text, p_card_id text, p_locked boolean
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_card_id is null or length(trim(p_card_id)) < 1 or length(p_card_id) > 80 or p_locked is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '카드 잠금 요청이 올바르지 않습니다.', greatest(coalesce(p_expected_revision, 0), 0), null, null);
  end if;
  v_request_hash := encode(digest(jsonb_build_object('type', 'setCardLock', 'expectedRevision', p_expected_revision, 'cardId', p_card_id, 'locked', p_locked)::text, 'sha256'), 'hex');
  select revision into v_revision from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태가 없습니다.', 0, null, null); end if;
  select * into v_previous from public.gacha_s2_idempotency where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'setCardLock' then
      return public.gacha_s2_command_error(p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '동일 요청 키를 재사용할 수 없습니다.', v_revision, null, null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key, 'VERSION_CONFLICT', '최신 상태를 다시 불러와야 합니다.', v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;
  update public.gacha_s2_player_cards set locked = p_locked, updated_at = now()
  where user_id = p_user_id and card_id = p_card_id and copies > 0;
  if not found then return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '보유 카드만 잠글 수 있습니다.', v_revision, null, null); end if;
  update public.gacha_s2_player_states set revision = revision + 1, updated_at = now()
  where user_id = p_user_id returning revision into v_revision;
  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object('contractVersion', 1, 'ok', true, 'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', 0, 'snapshot', v_snapshot,
    'result', jsonb_build_object('cardId', p_card_id, 'locked', p_locked));
  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response, expires_at)
  values (p_user_id, p_idempotency_key, 'setCardLock', v_request_hash, v_response, now() + interval '24 hours');
  insert into public.gacha_s2_command_audit (user_id, command_id, command_type, request_hash, expected_revision, committed_revision)
  values (p_user_id, p_idempotency_key, 'setCardLock', v_request_hash, p_expected_revision, v_revision);
  return v_response;
end;
$$;

revoke all on table public.gacha_s2_support_draws from public, anon, authenticated;
revoke all on function public.gacha_s2_weighted_json_pick(jsonb, bigint, integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_draw_pack_for_command(uuid, text, text, text, bigint, integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_purchase_support_pack(uuid, bigint, text, integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_use_support_item(uuid, bigint, text, text, text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_claim_idle_reward(uuid, bigint, text, numeric) from public, anon, authenticated;
revoke all on function public.gacha_s2_set_representative_card(uuid, bigint, text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_set_card_lock(uuid, bigint, text, text, boolean) from public, anon, authenticated;

grant execute on function public.gacha_s2_purchase_support_pack(uuid, bigint, text, integer) to service_role;
grant execute on function public.gacha_s2_use_support_item(uuid, bigint, text, text, text, text) to service_role;
grant execute on function public.gacha_s2_claim_idle_reward(uuid, bigint, text, numeric) to service_role;
grant execute on function public.gacha_s2_set_representative_card(uuid, bigint, text, text) to service_role;
grant execute on function public.gacha_s2_set_card_lock(uuid, bigint, text, text, boolean) to service_role;

commit;
