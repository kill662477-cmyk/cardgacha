-- 길드 M1 명령 RPC: 생성 · 해산 · 설정 변경 (PDB-16)
--
-- 기존 명령과 동일하게 멱등키 + expectedRevision + 감사 로그를 지킨다.
-- 다만 길드 명령은 gacha_s2_player_states 를 변경하지 않으므로 revision 을 올리지 않는다.
-- 올리면 진행 중인 다른 명령에 불필요한 VERSION_CONFLICT 를 유발할 뿐 이득이 없다.
-- 길드 상태는 gacha_s2_get_guild_state 로 별도 조회한다.

-- 길드 명령 공통 성공 응답. 각 RPC 의 반복을 줄인다.
create or replace function public.gacha_s2_guild_command_ok(
  p_user_id uuid,
  p_idempotency_key text,
  p_command_type text,
  p_request_hash text,
  p_revision bigint,
  p_result jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_response jsonb;
begin
  v_response := jsonb_build_object(
    'contractVersion', 1,
    'ok', true,
    'commandId', p_idempotency_key,
    'idempotencyKey', p_idempotency_key,
    'revision', p_revision,
    'serverTime', public.gacha_s2_now_ms(),
    'serverSeed', 0,
    'snapshot', public.gacha_s2_get_player_snapshot(p_user_id),
    'result', p_result
  );

  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, p_command_type, p_request_hash, v_response, now() + interval '24 hours'
  );

  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision
  ) values (
    p_user_id, p_idempotency_key, p_command_type, p_request_hash, p_revision, p_revision
  );

  return v_response;
end;
$$;

create or replace function public.gacha_s2_create_guild(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_name text,
  p_tag text,
  p_emblem text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_is_streamer boolean;
  v_name text := trim(coalesce(p_name, ''));
  v_tag text := nullif(trim(coalesce(p_tag, '')), '');
  v_emblem text := coalesce(nullif(trim(coalesce(p_emblem, '')), ''), 'shield');
  v_guild_id uuid;
begin
  -- 이름 내용 검증(비속어 등)은 두지 않는다. 길드장이 스트리머 본인이라 책임 소재가 명확하다.
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or length(v_name) < 2 or length(v_name) > 20
    or (v_tag is not null and length(v_tag) > 6) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '길드 생성 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, jsonb_build_object('field', 'name')
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'createGuild', 'expectedRevision', p_expected_revision,
    'name', v_name, 'tag', v_tag, 'emblem', v_emblem
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'createGuild' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등 키를 다른 요청에 사용할 수 없습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;

  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와 주세요.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null
    );
  end if;

  -- 길드 생성은 스트리머 전용이다.
  select is_streamer into v_is_streamer from public.gacha_s2_accounts where id = p_user_id;
  if not coalesce(v_is_streamer, false) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'FORBIDDEN', '길드는 방송인 계정만 만들 수 있습니다.', v_revision, null, null
    );
  end if;

  if exists (select 1 from public.gacha_s2_guild_membership(p_user_id)) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이미 소속된 길드가 있습니다.', v_revision, null, null
    );
  end if;

  if exists (
    select 1 from public.gacha_s2_guilds
    where lower(name) = lower(v_name) and disbanded_at is null
  ) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이미 사용 중인 길드 이름입니다.',
      v_revision, null, jsonb_build_object('field', 'name')
    );
  end if;

  if not exists (select 1 from public.gacha_s2_guild_emblems where emblem_key = v_emblem and active) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '사용할 수 없는 엠블럼입니다.',
      v_revision, null, jsonb_build_object('field', 'emblem')
    );
  end if;

  insert into public.gacha_s2_guilds (owner_user_id, name, tag, emblem)
  values (p_user_id, v_name, v_tag, v_emblem)
  returning guild_id into v_guild_id;

  insert into public.gacha_s2_guild_members (guild_id, user_id, role)
  values (v_guild_id, p_user_id, 'owner');

  -- 길드를 만들었으므로 본인이 넣어 둔 다른 길드 가입 신청은 모두 취소한다.
  update public.gacha_s2_guild_join_requests
  set status = 'cancelled', resolved_at = now(), resolved_by = p_user_id
  where user_id = p_user_id and status = 'pending';

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'createGuild', v_request_hash, v_revision,
    jsonb_build_object('guildId', v_guild_id, 'name', v_name)
  );
end;
$$;

create or replace function public.gacha_s2_disband_guild(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_guild_id uuid;
  v_role text;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '길드 해산 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'disbandGuild', 'expectedRevision', p_expected_revision
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'disbandGuild' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등 키를 다른 요청에 사용할 수 없습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;

  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와 주세요.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null
    );
  end if;

  select gm.guild_id, gm.role into v_guild_id, v_role
  from public.gacha_s2_guild_membership(p_user_id) gm;

  if v_guild_id is null or v_role <> 'owner' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'FORBIDDEN', '길드장만 해산할 수 있습니다.', v_revision, null, null
    );
  end if;

  update public.gacha_s2_guilds
  set disbanded_at = now(), updated_at = now()
  where guild_id = v_guild_id;

  -- 소속 행을 지운다. 남겨 두면 user_id 유일 인덱스 때문에 다른 길드에 가입할 수 없다.
  -- 해산은 길드원 귀책이 아니므로 재가입 페널티를 남기지 않는다(PDB-16 2.5).
  delete from public.gacha_s2_guild_members where guild_id = v_guild_id;

  update public.gacha_s2_guild_join_requests
  set status = 'cancelled', resolved_at = now(), resolved_by = p_user_id
  where guild_id = v_guild_id and status = 'pending';

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'disbandGuild', v_request_hash, v_revision,
    jsonb_build_object('guildId', v_guild_id)
  );
end;
$$;

create or replace function public.gacha_s2_update_guild_settings(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_notice text,
  p_emblem text,
  p_join_mode text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_guild_id uuid;
  v_role text;
  v_notice text := coalesce(p_notice, '');
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or length(v_notice) > 500
    or (p_join_mode is not null and p_join_mode not in ('approval', 'auto')) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '길드 설정 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'updateGuildSettings', 'expectedRevision', p_expected_revision,
    'notice', v_notice, 'emblem', p_emblem, 'joinMode', p_join_mode
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'updateGuildSettings' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등 키를 다른 요청에 사용할 수 없습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;

  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와 주세요.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null
    );
  end if;

  select gm.guild_id, gm.role into v_guild_id, v_role
  from public.gacha_s2_guild_membership(p_user_id) gm;

  -- 공지는 부길드장도 고칠 수 있지만, 엠블럼과 가입 방식은 길드장 전용이다.
  if v_guild_id is null or v_role not in ('owner', 'officer') then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'FORBIDDEN', '길드 설정을 변경할 권한이 없습니다.', v_revision, null, null
    );
  end if;
  if v_role <> 'owner' and (p_emblem is not null or p_join_mode is not null) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'FORBIDDEN', '엠블럼과 가입 방식은 길드장만 변경할 수 있습니다.', v_revision, null, null
    );
  end if;

  if p_emblem is not null and not exists (
    select 1 from public.gacha_s2_guild_emblems where emblem_key = p_emblem and active
  ) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '사용할 수 없는 엠블럼입니다.',
      v_revision, null, jsonb_build_object('field', 'emblem')
    );
  end if;

  update public.gacha_s2_guilds
  set notice = v_notice,
      emblem = coalesce(p_emblem, emblem),
      join_mode = coalesce(p_join_mode, join_mode),
      updated_at = now()
  where guild_id = v_guild_id;

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'updateGuildSettings', v_request_hash, v_revision,
    jsonb_build_object('guildId', v_guild_id)
  );
end;
$$;

revoke all on function public.gacha_s2_guild_command_ok(uuid, text, text, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.gacha_s2_create_guild(uuid, bigint, text, text, text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_disband_guild(uuid, bigint, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_update_guild_settings(uuid, bigint, text, text, text, text) from public, anon, authenticated;

grant execute on function public.gacha_s2_create_guild(uuid, bigint, text, text, text, text) to service_role;
grant execute on function public.gacha_s2_disband_guild(uuid, bigint, text) to service_role;
grant execute on function public.gacha_s2_update_guild_settings(uuid, bigint, text, text, text, text) to service_role;
