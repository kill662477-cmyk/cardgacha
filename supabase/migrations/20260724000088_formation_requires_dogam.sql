-- 편성 검증에 도감(collection_records) 등록 조건 추가.
-- 기존에는 보유(copies>0) + 비 EX 만 확인해, 테스트로 copies만 채워지고 도감 미등록인
-- 카드도 편성이 가능했다. 정상 계정은 보유 시 항상 도감이 등록되므로 영향이 없고,
-- 도감에 없는 카드는 출전에서 제외된다.
create or replace function public.gacha_s2_update_formation(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_formation text[]
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
  v_card_count integer;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_formation is null or cardinality(p_formation) < 1 or cardinality(p_formation) > 5 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '요청 형식이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null,
      jsonb_build_object('field', 'formation')
    );
  end if;

  if exists (
    select 1 from unnest(p_formation) as ids(card_id)
    where card_id is null or length(trim(card_id)) < 1 or length(card_id) > 80
  ) or (select count(distinct card_id) from unnest(p_formation) as ids(card_id)) <> cardinality(p_formation) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '편성 카드 ID가 올바르지 않습니다.',
      p_expected_revision, null, jsonb_build_object('field', 'formation')
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'updateFormation',
    'expectedRevision', p_expected_revision,
    'formation', to_jsonb(p_formation)
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states
  where user_id = p_user_id
  for update;
  if not found then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.',
      0, null, null
    );
  end if;

  select * into v_previous
  from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'updateFormation' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등성 키를 다른 요청에 사용할 수 없습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;

  if p_expected_revision <> v_revision then
    v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와야 합니다.',
      v_revision, v_snapshot, null
    );
  end if;

  -- 보유(copies>0) + 비 EX + 도감 등록(collection_records) 3조건을 모두 만족해야 편성 가능.
  select count(*) into v_card_count
  from public.gacha_s2_player_cards owned
  join public.gacha_s2_card_catalog catalog on catalog.card_id = owned.card_id
  where owned.user_id = p_user_id
    and owned.copies > 0
    and catalog.rarity <> 'EX'
    and owned.card_id = any(p_formation)
    and exists (
      select 1 from public.gacha_s2_collection_records cr
      where cr.user_id = p_user_id and cr.card_id = owned.card_id
    );

  if v_card_count <> cardinality(p_formation) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '도감에 없는 카드나 전투 불가 EX 카드는 편성할 수 없습니다.',
      v_revision, null, jsonb_build_object('field', 'formation')
    );
  end if;

  update public.gacha_s2_player_states
  set formation = p_formation,
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id
  returning revision into v_revision;

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1,
    'ok', true,
    'commandId', p_idempotency_key,
    'idempotencyKey', p_idempotency_key,
    'revision', v_revision,
    'serverTime', public.gacha_s2_now_ms(),
    'serverSeed', 0,
    'snapshot', v_snapshot,
    'result', jsonb_build_object('formation', to_jsonb(p_formation))
  );

  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'updateFormation', v_request_hash, v_response, now() + interval '24 hours'
  );

  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision
  ) values (
    p_user_id, p_idempotency_key, 'updateFormation', v_request_hash, p_expected_revision, v_revision
  );

  return v_response;
end;
$$;

revoke all on function public.gacha_s2_update_formation(uuid, bigint, text, text[]) from public, anon, authenticated;
grant execute on function public.gacha_s2_update_formation(uuid, bigint, text, text[]) to service_role;
