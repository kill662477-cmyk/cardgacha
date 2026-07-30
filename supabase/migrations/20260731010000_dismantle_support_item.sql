-- 보급품 분해. 인벤토리의 보급품을 소각해 포인트로 환급한다.
-- 환급 단가는 gacha_s2_balance_versions.config.supportItemDismantle.values 가 정본이고,
-- 그 값은 "보급팩 1회 가격 ÷ 해당 아이템 출현 확률"에서 유도된다(교환권은 팩 정가 상한).
-- values 에 없는 아이템(선택권 등)은 분해할 수 없다.
create or replace function public.gacha_s2_dismantle_support_item(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_item_id text,
  p_count integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_support_items jsonb;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_config jsonb;
  v_seed bigint;
  v_unit_points integer;
  v_owned integer;
  v_gained_points integer;
  v_remaining integer;
  v_snapshot jsonb;
  v_response jsonb;
begin
  -- 수량 상한 100000. 999 로 잡았다가 보유 1,000개 이상인 유저(655명, 최대 22,947개)의
  -- 전량 분해가 전부 거부된 사고가 있었다.
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_item_id is null or length(trim(p_item_id)) < 1 or length(p_item_id) > 80
    or p_count is null or p_count < 1 or p_count > 100000 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '분해 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'dismantleSupportItem', 'expectedRevision', p_expected_revision,
    'itemId', p_item_id, 'count', p_count
  )::text, 'sha256'), 'hex');

  select revision, support_items into v_revision, v_support_items
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
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'dismantleSupportItem' then
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
  if v_config is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '활성 밸런스 설정이 없습니다.', v_revision, null, null);
  end if;

  -- 분해 단가. 목록에 없으면 분해 불가 아이템이다(선택권 등).
  v_unit_points := (v_config->'supportItemDismantle'->'values'->>p_item_id)::integer;
  if v_unit_points is null or v_unit_points <= 0 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '분해할 수 없는 아이템입니다.', v_revision, null, null
    );
  end if;

  v_owned := coalesce((v_support_items->>p_item_id)::integer, 0);
  if v_owned < p_count then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '보유 수량이 부족합니다.', v_revision, null, null
    );
  end if;

  -- 분해에는 난수가 없지만 응답 계약이 serverSeed(32비트)를 필수로 요구한다.
  -- 이게 빠지면 클라이언트가 성공 응답을 거부해 "요청 처리 실패"가 뜬다(서버는 이미 커밋된 뒤라
  -- 아이템은 사라지고 화면만 실패로 보인다).
  v_seed := public.gacha_s2_new_seed();

  v_gained_points := v_unit_points * p_count;
  v_remaining := v_owned - p_count;
  v_support_items := jsonb_set(v_support_items, array[p_item_id], to_jsonb(v_remaining), true);

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
      'itemId', p_item_id,
      'dismantled', p_count,
      'unitPoints', v_unit_points,
      'gainedPoints', v_gained_points,
      'remaining', v_remaining
    )
  );

  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'dismantleSupportItem', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'dismantleSupportItem', v_request_hash, p_expected_revision, v_revision, v_seed
  );

  return v_response;
end;
$$;

revoke all on function public.gacha_s2_dismantle_support_item(uuid, bigint, text, text, integer)
from public, anon, authenticated;
grant execute on function public.gacha_s2_dismantle_support_item(uuid, bigint, text, text, integer)
to service_role;
