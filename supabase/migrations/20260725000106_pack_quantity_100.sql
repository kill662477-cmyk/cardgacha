-- 카드팩 100개 묶음 구매 허용(기존 1개 / 10개에 추가).
--
-- 월드보스·모험 보상이 늘면서 포인트가 남아돌아 10개씩 반복 구매가 번거롭다는 요청.
--
-- 부하 검증(프로덕션, 롤백 트랜잭션): 프리미엄 100팩 = 400뽑 루프가 940ms.
-- PostgREST statement_timeout 8초의 12% 수준이라 여유가 있다. 뽑기당 약 2.35ms.
-- 락은 본인 gacha_s2_player_states 행 하나뿐이라 유저 간 경합도 없다.
-- 오히려 10개씩 10번보다 gacha_s2_idempotency 행이 1/10 로 줄어 저장 부담이 작다.
--
-- 함수 본문은 p_quantity 를 그대로 곱해 쓰므로(v_total_cost / v_total_draws)
-- 입력 검증만 넓히면 된다. 나머지 로직은 건드리지 않는다.

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
    or p_quantity is null or p_quantity not in (1, 10, 100)
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

revoke all on function public.gacha_s2_purchase_pack(uuid, bigint, text, text, integer, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_purchase_pack(uuid, bigint, text, text, integer, text) to service_role;
