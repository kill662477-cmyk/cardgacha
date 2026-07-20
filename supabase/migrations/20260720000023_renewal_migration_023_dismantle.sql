-- Card Gacha Season 2: 카드 분해. 중복 카드(1장 보존, 잠금 제외)를 소각해
-- 카드 EXP 포션(cardExpPotionLarge)과 뽑기 포인트를 개별 확률 굴림으로 지급.
-- 등급이 높을수록 드롭 확률/포인트량 상승 (dropRates는 gacha_s2_balance_versions.config.dismantleRules 기반).
-- Run after migration 022. Service role only.

begin;

create or replace function public.gacha_s2_dismantle_cards(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_rarity text
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
  v_rule jsonb;
  v_potion_item text;
  v_seed bigint;
  v_card record;
  v_dismantlable integer;
  v_potion_rate numeric;
  v_points_rate numeric;
  v_points_amount integer;
  v_gained_potions integer := 0;
  v_gained_points integer := 0;
  v_dismantled_cards integer := 0;
  v_rolls jsonb := '[]'::jsonb;
  v_index integer := 0;
  v_potion_roll numeric;
  v_points_roll numeric;
  v_card_gained_potions integer;
  v_card_gained_points integer;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_rarity is null or p_rarity not in ('F','E','D','C','B','A','S','SS','SSS') then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '분해 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'dismantleCards', 'expectedRevision', p_expected_revision, 'rarity', p_rarity
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
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'dismantleCards' then
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

  -- 활성 밸런스에서 분해 규칙 읽기.
  select config into v_config from public.gacha_s2_balance_versions where active;
  if v_config is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '활성 밸런스 설정이 없습니다.', v_revision, null, null);
  end if;
  v_rule := v_config->'dismantleRules'->'dropRates'->p_rarity;
  v_potion_item := coalesce(v_config->'dismantleRules'->>'potionItem', 'cardExpPotionLarge');
  if v_rule is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '해당 등급은 분해할 수 없습니다.', v_revision, null, null);
  end if;
  v_potion_rate := (v_rule->>'potionRate')::numeric;
  v_points_rate := (v_rule->>'pointsRate')::numeric;
  v_points_amount := (v_rule->>'points')::integer;

  -- 결정론적 시드. 각 카드마다 카운터를 올려가며 2회 굴림(포션/포인트).
  v_seed := public.gacha_s2_new_seed();

  -- 대상: 해당 등급 보유 카드(copies > 1, 잠금 제외). 행잠금.
  for v_card in
    select owned.card_id, owned.copies
    from public.gacha_s2_player_cards owned
    join public.gacha_s2_card_catalog catalog on catalog.card_id = owned.card_id
    where owned.user_id = p_user_id
      and catalog.rarity = p_rarity
      and not owned.locked
      and owned.copies > 1
    for update of owned
  loop
    -- 보존 1장, 초과분 전부 분해.
    v_dismantlable := v_card.copies - 1;
    v_card_gained_potions := 0;
    v_card_gained_points := 0;
    while v_dismantlable > 0 loop
      v_potion_roll := public.gacha_s2_seed_roll(v_seed, v_index);
      v_points_roll := public.gacha_s2_seed_roll(v_seed, v_index + 100000);
      v_index := v_index + 1;
      if v_potion_roll < v_potion_rate then
        v_card_gained_potions := v_card_gained_potions + 1;
        v_gained_potions := v_gained_potions + 1;
      end if;
      if v_points_roll < v_points_rate then
        v_card_gained_points := v_card_gained_points + v_points_amount;
        v_gained_points := v_gained_points + v_points_amount;
      end if;
      v_dismantlable := v_dismantlable - 1;
    end loop;
    v_dismantled_cards := v_dismantled_cards + (v_card.copies - 1);
    v_rolls := v_rolls || jsonb_build_object(
      'cardId', v_card.card_id, 'dismantled', v_card.copies - 1,
      'potions', v_card_gained_potions, 'points', v_card_gained_points
    );
  end loop;

  -- 분해 대상이 없으면 거부(무의미한 요청 방지).
  if v_dismantled_cards = 0 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '해당 등급에 분해할 중복 카드가 없습니다.',
      v_revision, null, null
    );
  end if;

  -- copies 차감: 보존 1장 남기고 전부 소각.
  update public.gacha_s2_player_cards owned
  set copies = 1, updated_at = now()
  from public.gacha_s2_card_catalog catalog
  where owned.user_id = p_user_id
    and owned.card_id = catalog.card_id
    and catalog.rarity = p_rarity
    and not owned.locked
    and owned.copies > 1;

  -- 보상 반영.
  if v_gained_potions > 0 then
    v_support_items := jsonb_set(
      v_support_items,
      array[v_potion_item],
      to_jsonb(coalesce((v_support_items->>v_potion_item)::integer, 0) + v_gained_potions),
      true
    );
  end if;
  update public.gacha_s2_player_states
  set points = points + v_gained_points,
      support_items = v_support_items,
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
      'rarity', p_rarity,
      'dismantledCards', v_dismantled_cards,
      'gainedPotions', v_gained_potions,
      'gainedPoints', v_gained_points,
      'potionItem', v_potion_item,
      'rolls', v_rolls
    )
  );

  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'dismantleCards', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'dismantleCards', v_request_hash, p_expected_revision, v_revision, v_seed
  );
  return v_response;
end;
$$;

revoke all on function public.gacha_s2_dismantle_cards(uuid, bigint, text, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_dismantle_cards(uuid, bigint, text, text) to service_role;

commit;
