-- Card Gacha Season 2: atomic card-pack purchase and enhancement commands.
-- REVIEW ONLY. Run after migrations 001-003. Service role only.

begin;

do $$
begin
  if to_regclass('public.gacha_s2_balance_versions') is null
    or to_regclass('public.gacha_s2_collection_records') is null
    or to_regclass('public.gacha_s2_command_audit') is null then
    raise exception 'missing Season 2 command schema: run migrations 001-003 first';
  end if;
end;
$$;

alter table public.gacha_s2_command_audit
  add column if not exists server_seed bigint check (server_seed between 0 and 4294967295);

create table if not exists public.gacha_s2_pack_draws (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  command_id text not null,
  draw_index integer not null check (draw_index >= 0),
  product_id text not null check (product_id in ('general','elite','premium','race')),
  race text,
  card_id text not null references public.gacha_s2_card_catalog(card_id),
  rarity text not null check (rarity in ('F','E','D','C','B','A','S','SS','SSS')),
  server_seed bigint not null check (server_seed between 0 and 4294967295),
  created_at timestamptz not null default now(),
  check (
    (product_id = 'race' and race in ('저그','테란','프로토스'))
    or (product_id <> 'race' and race is null)
  ),
  unique (user_id, command_id, draw_index)
);

create table if not exists public.gacha_s2_enhancement_results (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  command_id text not null,
  card_id text not null references public.gacha_s2_card_catalog(card_id),
  from_enhancement integer not null check (from_enhancement between 0 and 8),
  target_enhancement integer not null check (target_enhancement = from_enhancement + 1),
  final_enhancement integer not null check (final_enhancement between 0 and 9),
  outcome text not null check (outcome in ('success','fail','destroy')),
  destruction_blocked boolean not null default false,
  success_rate numeric not null check (success_rate between 0 and 100),
  destroy_rate numeric not null check (destroy_rate between 0 and 100),
  roll numeric not null check (roll >= 0 and roll < 100),
  booster_id text check (booster_id is null or booster_id in ('enhance5','enhance10','destructionGuard')),
  materials jsonb not null check (jsonb_typeof(materials) = 'array'),
  points_spent integer not null check (points_spent in (0, 5000)),
  server_seed bigint not null check (server_seed between 0 and 4294967295),
  created_at timestamptz not null default now(),
  check (not destruction_blocked or (outcome = 'fail' and booster_id = 'destructionGuard')),
  unique (user_id, command_id)
);

create index if not exists idx_gacha_s2_pack_draws_user_created
  on public.gacha_s2_pack_draws(user_id, created_at desc);
create index if not exists idx_gacha_s2_enhancement_results_user_created
  on public.gacha_s2_enhancement_results(user_id, created_at desc);

alter table public.gacha_s2_pack_draws enable row level security;
alter table public.gacha_s2_enhancement_results enable row level security;

create or replace function public.gacha_s2_new_seed()
returns bigint
language sql
volatile
as $$
  select (('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint);
$$;

create or replace function public.gacha_s2_seed_roll(p_seed bigint, p_counter integer)
returns numeric
language sql
immutable
strict
as $$
  select (('x' || substr(encode(digest(p_seed::text || ':' || p_counter::text, 'sha256'), 'hex'), 1, 8))::bit(32)::bigint)::numeric
    / 4294967296::numeric;
$$;

create or replace function public.gacha_s2_purchase_pack(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_product_id text,
  p_quantity integer,
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
  v_pack jsonb;
  v_pack_price integer;
  v_pack_count integer;
  v_total_cost integer;
  v_total_draws integer;
  v_points integer;
  v_seed bigint;
  v_roll numeric;
  v_rarity text;
  v_candidate_count integer;
  v_card_id text;
  v_results jsonb := '[]'::jsonb;
  v_snapshot jsonb;
  v_response jsonb;
  v_index integer;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_product_id is null or p_product_id not in ('general','elite','premium','race')
    or p_quantity is null or p_quantity not in (1, 10)
    or (p_product_id = 'race' and (p_race is null or p_race not in ('저그','테란','프로토스')))
    or (p_product_id <> 'race' and p_race is not null) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '카드팩 구매 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'purchasePack', 'expectedRevision', p_expected_revision,
    'productId', p_product_id, 'quantity', p_quantity, 'race', p_race
  )::text, 'sha256'), 'hex');

  select revision, points into v_revision, v_points
  from public.gacha_s2_player_states
  where user_id = p_user_id
  for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous
  from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'purchasePack' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등성 키를 다른 요청에 사용할 수 없습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;

  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와야 합니다.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null
    );
  end if;

  select config into v_config from public.gacha_s2_balance_versions where active;
  v_pack := v_config->'packs'->p_product_id;
  if v_pack is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '활성 카드팩 설정이 없습니다.', v_revision, null, null);
  end if;

  v_pack_price := (v_pack->>'price')::integer;
  v_pack_count := (v_pack->>'count')::integer;
  v_total_cost := v_pack_price * p_quantity;
  v_total_draws := v_pack_count * p_quantity;
  if v_points < v_total_cost then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '포인트가 부족합니다.', v_revision, null, null);
  end if;

  v_seed := public.gacha_s2_new_seed();
  for v_index in 0..(v_total_draws - 1) loop
    v_roll := public.gacha_s2_seed_roll(v_seed, v_index * 2);
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
    if v_candidate_count < 1 then raise exception 'no eligible card for pack rarity %', v_rarity; end if;

    select card_id into v_card_id
    from public.gacha_s2_card_catalog
    where rarity = v_rarity and not is_group
      and (p_product_id <> 'race' or race = p_race)
    order by card_id
    offset floor(public.gacha_s2_seed_roll(v_seed, v_index * 2 + 1) * v_candidate_count)::integer
    limit 1;

    insert into public.gacha_s2_player_cards (user_id, card_id, copies)
    values (p_user_id, v_card_id, 1)
    on conflict (user_id, card_id) do update
      set copies = public.gacha_s2_player_cards.copies + 1, updated_at = now();
    insert into public.gacha_s2_collection_records (user_id, card_id)
    values (p_user_id, v_card_id)
    on conflict (user_id, card_id) do nothing;
    insert into public.gacha_s2_pack_draws (
      user_id, command_id, draw_index, product_id, race, card_id, rarity, server_seed
    ) values (
      p_user_id, p_idempotency_key, v_index, p_product_id, p_race, v_card_id, v_rarity, v_seed
    );
    v_results := v_results || jsonb_build_array(jsonb_build_object('cardId', v_card_id, 'rarity', v_rarity));
  end loop;

  update public.gacha_s2_player_states
  set points = points - v_total_cost,
      shop_transactions = shop_transactions + 1,
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id
  returning revision into v_revision;

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true,
    'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', v_seed,
    'snapshot', v_snapshot,
    'result', jsonb_build_object(
      'productId', p_product_id, 'quantity', p_quantity, 'race', p_race,
      'spentPoints', v_total_cost, 'cards', v_results
    )
  );

  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'purchasePack', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'purchasePack', v_request_hash, p_expected_revision, v_revision, v_seed
  );
  return v_response;
end;
$$;

create or replace function public.gacha_s2_enhance_card(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_card_id text,
  p_target_enhancement integer,
  p_material_card_ids text[],
  p_booster_id text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_points integer;
  v_support_items jsonb;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_config jsonb;
  v_target record;
  v_rule jsonb;
  v_required_exp integer;
  v_point_cost integer := 0;
  v_booster text := coalesce(p_booster_id, 'none');
  v_booster_bonus integer := 0;
  v_seed bigint;
  v_roll numeric;
  v_base_success numeric;
  v_penalty numeric := 0;
  v_success_rate numeric;
  v_destroy_rate numeric;
  v_outcome text;
  v_blocked boolean := false;
  v_final_enhancement integer;
  v_invalid_materials integer;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_card_id is null or length(trim(p_card_id)) < 1 or length(p_card_id) > 80
    or p_target_enhancement is null or p_target_enhancement not between 1 and 9
    or p_material_card_ids is null or cardinality(p_material_card_ids) < 1 or cardinality(p_material_card_ids) > 3
    or v_booster not in ('none','enhance5','enhance10','destructionGuard')
    or exists (
      select 1 from unnest(p_material_card_ids) as ids(card_id)
      where card_id is null or length(trim(card_id)) < 1 or length(card_id) > 80
    ) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '강화 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'enhanceCard', 'expectedRevision', p_expected_revision,
    'cardId', p_card_id, 'targetEnhancement', p_target_enhancement,
    'materialCardIds', to_jsonb(p_material_card_ids), 'boosterId', v_booster
  )::text, 'sha256'), 'hex');

  select revision, points, support_items into v_revision, v_points, v_support_items
  from public.gacha_s2_player_states
  where user_id = p_user_id
  for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous
  from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'enhanceCard' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등성 키를 다른 요청에 사용할 수 없습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;

  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와야 합니다.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null
    );
  end if;

  select owned.card_id, owned.copies, owned.enhancement, owned.card_exp, owned.locked, catalog.rarity
  into v_target
  from public.gacha_s2_player_cards owned
  join public.gacha_s2_card_catalog catalog on catalog.card_id = owned.card_id
  where owned.user_id = p_user_id and owned.card_id = p_card_id
  for update of owned;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '강화할 수 없는 카드입니다.', v_revision, null, null);
  end if;
  if v_target.copies < 1 or v_target.rarity = 'EX' then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '강화할 수 없는 카드입니다.', v_revision, null, null);
  end if;
  if v_target.enhancement >= 9 or p_target_enhancement <> v_target.enhancement + 1 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '현재 강화 단계와 요청 단계가 맞지 않습니다.', v_revision, null, null);
  end if;

  select config into v_config from public.gacha_s2_balance_versions where active;
  if v_config is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '활성 강화 설정이 없습니다.', v_revision, null, null);
  end if;
  v_required_exp := (v_config->'enhancement'->'expRequirements'->>(v_target.enhancement))::integer;
  if v_target.card_exp < v_required_exp then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '카드 경험치가 부족합니다.', v_revision, null, null);
  end if;

  select rule into v_rule
  from jsonb_array_elements(v_config->'materialRules'->(v_target.rarity)) as rules(rule)
  where (rule->>'count')::integer = cardinality(p_material_card_ids)
    and (
      select count(*)
      from unnest(p_material_card_ids) as ids(card_id)
      join public.gacha_s2_card_catalog catalog on catalog.card_id = ids.card_id
      where catalog.rarity = rule->>'rarity'
    ) = cardinality(p_material_card_ids)
  limit 1;
  if v_rule is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '강화 재료 등급이나 수량이 맞지 않습니다.', v_revision, null, null);
  end if;

  with requested as (
    select card_id, count(*)::integer as requested_count
    from unnest(p_material_card_ids) as ids(card_id)
    group by card_id
  )
  select count(*) into v_invalid_materials
  from requested req
  left join public.gacha_s2_player_cards owned
    on owned.user_id = p_user_id and owned.card_id = req.card_id
  left join public.gacha_s2_card_catalog catalog on catalog.card_id = req.card_id
  where owned.card_id is null
    or (owned.locked and req.card_id <> p_card_id)
    or catalog.rarity <> v_rule->>'rarity'
    or req.requested_count > owned.copies - 1;
  if v_invalid_materials > 0 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '잠금 카드 또는 마지막 1장은 강화 재료로 사용할 수 없습니다.',
      v_revision, null, null
    );
  end if;

  if p_target_enhancement = 9 then
    v_point_cost := (v_config->'enhancement'->>'plusNinePointCost')::integer;
    if v_points < v_point_cost then
      return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '9성 강화 포인트가 부족합니다.', v_revision, null, null);
    end if;
  end if;
  if v_booster in ('enhance5','enhance10') and p_target_enhancement < 4 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '강화 촉진제는 4성부터 사용할 수 있습니다.', v_revision, null, null);
  end if;
  if v_booster = 'destructionGuard' and p_target_enhancement < 7 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '파괴 차단제는 7성부터 사용할 수 있습니다.', v_revision, null, null);
  end if;
  if v_booster <> 'none' and coalesce((v_support_items->>v_booster)::integer, 0) < 1 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '선택한 강화 보조제가 없습니다.', v_revision, null, null);
  end if;

  v_base_success := (v_config->'enhancement'->'baseSuccessRates'->>(p_target_enhancement))::numeric;
  v_destroy_rate := (v_config->'enhancement'->'destroyRates'->>(p_target_enhancement))::numeric;
  if p_target_enhancement > 3 then
    v_penalty := (v_config->'enhancement'->'rarityPenalties'->>v_target.rarity)::numeric;
  end if;
  if v_booster = 'enhance5' then v_booster_bonus := 5;
  elsif v_booster = 'enhance10' then v_booster_bonus := 10;
  end if;
  if p_target_enhancement <= 3 then v_success_rate := 100;
  else v_success_rate := least(95, greatest(0, v_base_success - v_penalty + v_booster_bonus));
  end if;

  v_seed := public.gacha_s2_new_seed();
  v_roll := public.gacha_s2_seed_roll(v_seed, 0) * 100;
  if v_roll < v_success_rate then
    v_outcome := 'success';
    v_final_enhancement := p_target_enhancement;
  elsif v_roll < v_success_rate + v_destroy_rate then
    if v_booster = 'destructionGuard' then
      v_outcome := 'fail';
      v_blocked := true;
      v_final_enhancement := v_target.enhancement;
    else
      v_outcome := 'destroy';
      v_final_enhancement := 0;
    end if;
  else
    v_outcome := 'fail';
    v_final_enhancement := v_target.enhancement;
  end if;

  with requested as (
    select card_id, count(*)::integer as requested_count
    from unnest(p_material_card_ids) as ids(card_id)
    group by card_id
  )
  update public.gacha_s2_player_cards owned
  set copies = owned.copies - req.requested_count,
      updated_at = now()
  from requested req
  where owned.user_id = p_user_id and owned.card_id = req.card_id;

  if v_outcome = 'success' then
    update public.gacha_s2_player_cards
    set enhancement = p_target_enhancement, card_exp = 0, updated_at = now()
    where user_id = p_user_id and card_id = p_card_id;
  elsif v_outcome = 'destroy' then
    update public.gacha_s2_player_cards
    set enhancement = 0, card_exp = 0, updated_at = now()
    where user_id = p_user_id and card_id = p_card_id;
  end if;

  if v_booster <> 'none' then
    v_support_items := jsonb_set(
      v_support_items, array[v_booster], to_jsonb((v_support_items->>v_booster)::integer - 1), false
    );
  end if;
  update public.gacha_s2_player_states
  set points = points - v_point_cost,
      support_items = v_support_items,
      enhancement_attempts = enhancement_attempts + 1,
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id
  returning revision into v_revision;

  insert into public.gacha_s2_enhancement_results (
    user_id, command_id, card_id, from_enhancement, target_enhancement, final_enhancement,
    outcome, destruction_blocked, success_rate, destroy_rate, roll, booster_id,
    materials, points_spent, server_seed
  ) values (
    p_user_id, p_idempotency_key, p_card_id, v_target.enhancement, p_target_enhancement, v_final_enhancement,
    v_outcome, v_blocked, v_success_rate, v_destroy_rate, v_roll, nullif(v_booster, 'none'),
    to_jsonb(p_material_card_ids), v_point_cost, v_seed
  );

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true,
    'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', v_seed,
    'snapshot', v_snapshot,
    'result', jsonb_build_object(
      'cardId', p_card_id, 'targetEnhancement', p_target_enhancement,
      'finalEnhancement', v_final_enhancement, 'outcome', v_outcome,
      'destructionBlocked', v_blocked, 'successRate', v_success_rate,
      'destroyRate', v_destroy_rate, 'roll', v_roll,
      'materials', to_jsonb(p_material_card_ids), 'spentPoints', v_point_cost
    )
  );

  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'enhanceCard', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'enhanceCard', v_request_hash, p_expected_revision, v_revision, v_seed
  );
  return v_response;
end;
$$;

revoke all on table public.gacha_s2_pack_draws from public, anon, authenticated;
revoke all on table public.gacha_s2_enhancement_results from public, anon, authenticated;
revoke all on function public.gacha_s2_new_seed() from public, anon, authenticated;
revoke all on function public.gacha_s2_seed_roll(bigint, integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_purchase_pack(uuid, bigint, text, text, integer, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_enhance_card(uuid, bigint, text, text, integer, text[], text) from public, anon, authenticated;

grant execute on function public.gacha_s2_purchase_pack(uuid, bigint, text, text, integer, text) to service_role;
grant execute on function public.gacha_s2_enhance_card(uuid, bigint, text, text, integer, text[], text) to service_role;

commit;
