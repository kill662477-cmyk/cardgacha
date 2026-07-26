create or replace function public.gacha_s2_formation_preset_cards_ok(
  p_user_id uuid, p_formation text[]
) returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select count(*) = cardinality(p_formation)
  from public.gacha_s2_player_cards owned
  join public.gacha_s2_card_catalog catalog on catalog.card_id = owned.card_id
  where owned.user_id = p_user_id and owned.copies > 0 and catalog.rarity <> 'EX'
    and owned.card_id = any(p_formation)
    and exists (select 1 from public.gacha_s2_collection_records cr
                where cr.user_id = p_user_id and cr.card_id = owned.card_id);
$$;

create or replace function public.gacha_s2_formation_preset_ok(
  p_user_id uuid, p_idempotency_key text, p_command_type text,
  p_request_hash text, p_revision bigint, p_result jsonb
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_response jsonb;
begin
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true,
    'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', p_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', 0,
    'snapshot', public.gacha_s2_get_player_snapshot(p_user_id), 'result', p_result);
  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response, expires_at)
  values (p_user_id, p_idempotency_key, p_command_type, p_request_hash, v_response, now() + interval '24 hours');
  insert into public.gacha_s2_command_audit (user_id, command_id, command_type, request_hash, expected_revision, committed_revision)
  values (p_user_id, p_idempotency_key, p_command_type, p_request_hash, p_revision - 1, p_revision);
  return v_response;
end;
$$;

create or replace function public.gacha_s2_save_formation_preset(
  p_user_id uuid, p_expected_revision bigint, p_idempotency_key text,
  p_preset_id text, p_formation text[]
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_revision bigint; v_request_hash text; v_previous public.gacha_s2_idempotency%rowtype;
  v_presets jsonb; v_name text := trim(coalesce(p_preset_id, ''));
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or length(v_name) < 1 or length(v_name) > 12
    or p_formation is null or cardinality(p_formation) <> 5
    or (select count(distinct card_id) from unnest(p_formation) as ids(card_id)) <> 5 then
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED',
      '프리셋 요청 형식이 올바르지 않습니다.', greatest(coalesce(p_expected_revision, 0), 0), null,
      jsonb_build_object('field', 'preset'));
  end if;
  v_request_hash := encode(digest(jsonb_build_object('type','saveFormationPreset',
    'expectedRevision',p_expected_revision,'presetId',v_name,'formation',to_jsonb(p_formation))::text,'sha256'),'hex');
  select revision, formation_presets into v_revision, v_presets
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key,'AUTH_REQUIRED','계정 상태를 찾을 수 없습니다.',0,null,null);
  end if;
  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'saveFormationPreset' then
      return public.gacha_s2_command_error(p_idempotency_key,'IDEMPOTENCY_KEY_REUSED',
        '같은 멱등성 키를 다른 요청에 사용할 수 없습니다.', v_revision,null,null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key,'VERSION_CONFLICT','최신 기록을 다시 불러와야 합니다.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;
  v_presets := coalesce(v_presets, '{}'::jsonb);
  if not (v_presets ? v_name) and (select count(*) from jsonb_object_keys(v_presets)) >= 5 then
    return public.gacha_s2_command_error(p_idempotency_key,'COMMAND_REJECTED',
      '프리셋은 최대 5개까지 저장할 수 있습니다.', v_revision, null, jsonb_build_object('field','preset'));
  end if;
  if not public.gacha_s2_formation_preset_cards_ok(p_user_id, p_formation) then
    return public.gacha_s2_command_error(p_idempotency_key,'COMMAND_REJECTED',
      '도감에 없는 카드나 전투 불가 EX 카드는 저장할 수 없습니다.', v_revision, null, jsonb_build_object('field','formation'));
  end if;
  update public.gacha_s2_player_states
  set formation_presets = v_presets || jsonb_build_object(v_name, to_jsonb(p_formation)),
      revision = revision + 1, updated_at = now()
  where user_id = p_user_id returning revision into v_revision;
  return public.gacha_s2_formation_preset_ok(p_user_id, p_idempotency_key, 'saveFormationPreset',
    v_request_hash, v_revision, jsonb_build_object('presetId', v_name, 'formation', to_jsonb(p_formation)));
end;
$$;

create or replace function public.gacha_s2_apply_formation_preset(
  p_user_id uuid, p_expected_revision bigint, p_idempotency_key text, p_preset_id text
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_revision bigint; v_request_hash text; v_previous public.gacha_s2_idempotency%rowtype;
  v_presets jsonb; v_formation text[]; v_name text := trim(coalesce(p_preset_id, ''));
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or length(v_name) < 1 or length(v_name) > 12 then
    return public.gacha_s2_command_error(p_idempotency_key,'VALIDATION_FAILED',
      '프리셋 요청 형식이 올바르지 않습니다.', greatest(coalesce(p_expected_revision,0),0), null,
      jsonb_build_object('field','preset'));
  end if;
  v_request_hash := encode(digest(jsonb_build_object('type','applyFormationPreset',
    'expectedRevision',p_expected_revision,'presetId',v_name)::text,'sha256'),'hex');
  select revision, formation_presets into v_revision, v_presets
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key,'AUTH_REQUIRED','계정 상태를 찾을 수 없습니다.',0,null,null);
  end if;
  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'applyFormationPreset' then
      return public.gacha_s2_command_error(p_idempotency_key,'IDEMPOTENCY_KEY_REUSED',
        '같은 멱등성 키를 다른 요청에 사용할 수 없습니다.', v_revision,null,null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key,'VERSION_CONFLICT','최신 기록을 다시 불러와야 합니다.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;
  v_presets := coalesce(v_presets, '{}'::jsonb);
  if not (v_presets ? v_name) then
    return public.gacha_s2_command_error(p_idempotency_key,'COMMAND_REJECTED','해당 프리셋이 없습니다.',
      v_revision, null, jsonb_build_object('field','preset'));
  end if;
  select array_agg(value::text order by ord) into v_formation
  from jsonb_array_elements_text(v_presets->v_name) with ordinality as x(value, ord);
  if v_formation is null or cardinality(v_formation) <> 5
    or not public.gacha_s2_formation_preset_cards_ok(p_user_id, v_formation) then
    return public.gacha_s2_command_error(p_idempotency_key,'COMMAND_REJECTED',
      '프리셋의 카드 중 지금 편성할 수 없는 카드가 있습니다.', v_revision, null, jsonb_build_object('field','formation'));
  end if;
  update public.gacha_s2_player_states
  set formation = v_formation, active_formation_preset_id = v_name,
      revision = revision + 1, updated_at = now()
  where user_id = p_user_id returning revision into v_revision;
  return public.gacha_s2_formation_preset_ok(p_user_id, p_idempotency_key, 'applyFormationPreset',
    v_request_hash, v_revision, jsonb_build_object('presetId', v_name, 'formation', to_jsonb(v_formation)));
end;
$$;

create or replace function public.gacha_s2_delete_formation_preset(
  p_user_id uuid, p_expected_revision bigint, p_idempotency_key text, p_preset_id text
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_revision bigint; v_request_hash text; v_previous public.gacha_s2_idempotency%rowtype;
  v_presets jsonb; v_active text; v_name text := trim(coalesce(p_preset_id, ''));
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or length(v_name) < 1 or length(v_name) > 12 then
    return public.gacha_s2_command_error(p_idempotency_key,'VALIDATION_FAILED',
      '프리셋 요청 형식이 올바르지 않습니다.', greatest(coalesce(p_expected_revision,0),0), null,
      jsonb_build_object('field','preset'));
  end if;
  v_request_hash := encode(digest(jsonb_build_object('type','deleteFormationPreset',
    'expectedRevision',p_expected_revision,'presetId',v_name)::text,'sha256'),'hex');
  select revision, formation_presets, active_formation_preset_id
    into v_revision, v_presets, v_active
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key,'AUTH_REQUIRED','계정 상태를 찾을 수 없습니다.',0,null,null);
  end if;
  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'deleteFormationPreset' then
      return public.gacha_s2_command_error(p_idempotency_key,'IDEMPOTENCY_KEY_REUSED',
        '같은 멱등성 키를 다른 요청에 사용할 수 없습니다.', v_revision,null,null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key,'VERSION_CONFLICT','최신 기록을 다시 불러와야 합니다.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;
  v_presets := coalesce(v_presets, '{}'::jsonb);
  if not (v_presets ? v_name) then
    return public.gacha_s2_command_error(p_idempotency_key,'COMMAND_REJECTED','해당 프리셋이 없습니다.',
      v_revision, null, jsonb_build_object('field','preset'));
  end if;
  update public.gacha_s2_player_states
  set formation_presets = v_presets - v_name,
      active_formation_preset_id = case when v_active = v_name then null else v_active end,
      revision = revision + 1, updated_at = now()
  where user_id = p_user_id returning revision into v_revision;
  return public.gacha_s2_formation_preset_ok(p_user_id, p_idempotency_key, 'deleteFormationPreset',
    v_request_hash, v_revision, jsonb_build_object('presetId', v_name));
end;
$$;

revoke all on function public.gacha_s2_formation_preset_cards_ok(uuid, text[]) from public, anon, authenticated;
revoke all on function public.gacha_s2_formation_preset_ok(uuid, text, text, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.gacha_s2_save_formation_preset(uuid, bigint, text, text, text[]) from public, anon, authenticated;
revoke all on function public.gacha_s2_apply_formation_preset(uuid, bigint, text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_delete_formation_preset(uuid, bigint, text, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_save_formation_preset(uuid, bigint, text, text, text[]) to service_role;
grant execute on function public.gacha_s2_apply_formation_preset(uuid, bigint, text, text) to service_role;
grant execute on function public.gacha_s2_delete_formation_preset(uuid, bigint, text, text) to service_role;;
