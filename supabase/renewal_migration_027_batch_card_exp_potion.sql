-- Card Gacha Season 2: batch-use card EXP potions ("일괄 채우기").
--
-- Adds an optional p_count to gacha_s2_use_support_item so the enhancement
-- screen can consume up to `count` potions of one type in a single command
-- instead of one round trip per potion. Scoped to the cardExp branch only --
-- every other item type (energy, buffs, resets, packs) still consumes exactly
-- 1 regardless of what a client sends, so this can't be used to batch-buy
-- packs or batch-reset run counters.
--
-- Actual amount used is still capped server-side by both owned quantity and
-- the target card's remaining required EXP -- p_count is a ceiling, not a
-- guarantee; client fills in whatever the button offers (usually "as many as
-- owned, up to what's needed").

-- Adding a parameter creates a new overload rather than replacing the old one
-- (Postgres keys functions on the full signature) -- drop the 6-arg version
-- first so callers can't accidentally hit the pre-batch overload.
drop function if exists public.gacha_s2_use_support_item(uuid, bigint, text, text, text, text);

create or replace function public.gacha_s2_use_support_item(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_item_id text,
  p_target_card_id text default null,
  p_race text default null,
  p_count integer default 1
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
  v_consumed integer := 1;
  v_use_count integer;
  v_now_ms bigint := public.gacha_s2_now_ms();
  v_end_ms bigint;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_item_id is null or length(p_item_id) > 80
    or p_count is null or p_count < 1 or p_count > 9999 then
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '아이템 사용 요청이 올바르지 않습니다.', greatest(coalesce(p_expected_revision, 0), 0), null, null);
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'useSupportItem', 'expectedRevision', p_expected_revision,
    'itemId', p_item_id, 'targetCardId', p_target_card_id, 'race', p_race, 'count', p_count
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
    v_use_count := least(
      p_count,
      (v_items->>p_item_id)::integer,
      ceil((v_required - v_current_exp)::numeric / (v_item->>'cardExp')::integer)::integer
    );
    v_consumed := v_use_count;
    v_gained := least((v_item->>'cardExp')::integer * v_use_count, v_required - v_current_exp);
    update public.gacha_s2_player_cards set card_exp = card_exp + v_gained, updated_at = now()
    where user_id = p_user_id and card_id = p_target_card_id;
    v_result := jsonb_build_object('itemId', p_item_id, 'cardId', p_target_card_id, 'cardExpGained', v_gained, 'potionsUsed', v_consumed);
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
  set support_items = jsonb_set(support_items, array[p_item_id], to_jsonb((support_items->>p_item_id)::integer - v_consumed), true),
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

revoke all on function public.gacha_s2_use_support_item(uuid, bigint, text, text, text, text, integer) from public, anon, authenticated;
