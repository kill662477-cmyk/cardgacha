-- 길드 M1 명령 RPC: 탈퇴 · 추방 · 역할 변경 (PDB-16)
--
-- 탈퇴와 추방은 모두 3일 재가입 페널티를 남긴다. 길드를 옮겨 다니며 보상을
-- 중복 수령하는 것을 막기 위해서다. 해산으로 소속이 사라지는 경우에는
-- 본인 귀책이 아니므로 페널티를 남기지 않는다(gacha_s2_disband_guild).

create or replace function public.gacha_s2_guild_apply_penalty(p_user_id uuid, p_reason text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.gacha_s2_guild_leave_penalties (user_id, left_at, penalty_until, reason)
  values (p_user_id, now(), now() + interval '3 days', p_reason)
  on conflict (user_id) do update
  set left_at = now(), penalty_until = now() + interval '3 days', reason = excluded.reason;
$$;

create or replace function public.gacha_s2_leave_guild(
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
      p_idempotency_key, 'VALIDATION_FAILED', '탈퇴 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'leaveGuild', 'expectedRevision', p_expected_revision
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'leaveGuild' then
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
  if v_guild_id is null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '소속된 길드가 없습니다.', v_revision, null, null
    );
  end if;

  -- 길드장은 탈퇴할 수 없다. 길드를 정리하려면 해산해야 한다.
  if v_role = 'owner' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '길드장은 탈퇴할 수 없습니다. 길드를 해산해 주세요.',
      v_revision, null, null
    );
  end if;

  delete from public.gacha_s2_guild_members where guild_id = v_guild_id and user_id = p_user_id;
  perform public.gacha_s2_guild_apply_penalty(p_user_id, 'leave');

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'leaveGuild', v_request_hash, v_revision,
    jsonb_build_object('guildId', v_guild_id)
  );
end;
$$;

create or replace function public.gacha_s2_kick_guild_member(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_target_user_id uuid
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
  v_target_role text;
begin
  if p_user_id is null or p_target_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '추방 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  if p_user_id = p_target_user_id then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '자기 자신을 추방할 수 없습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'kickGuildMember', 'expectedRevision', p_expected_revision, 'targetUserId', p_target_user_id
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'kickGuildMember' then
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
  if v_guild_id is null or v_role not in ('owner', 'officer') then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'FORBIDDEN', '추방할 권한이 없습니다.', v_revision, null, null
    );
  end if;

  select role into v_target_role
  from public.gacha_s2_guild_members
  where guild_id = v_guild_id and user_id = p_target_user_id;
  if v_target_role is null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '같은 길드의 길드원이 아닙니다.', v_revision, null, null
    );
  end if;

  if v_target_role = 'owner' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'FORBIDDEN', '길드장은 추방할 수 없습니다.', v_revision, null, null
    );
  end if;
  -- 부길드장끼리 서로 추방하지 못하게 한다. 부길드장 추방은 길드장만 가능하다.
  if v_target_role = 'officer' and v_role <> 'owner' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'FORBIDDEN', '부길드장은 길드장만 추방할 수 있습니다.', v_revision, null, null
    );
  end if;

  delete from public.gacha_s2_guild_members where guild_id = v_guild_id and user_id = p_target_user_id;
  perform public.gacha_s2_guild_apply_penalty(p_target_user_id, 'kick');

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'kickGuildMember', v_request_hash, v_revision,
    jsonb_build_object('guildId', v_guild_id, 'targetUserId', p_target_user_id)
  );
end;
$$;

create or replace function public.gacha_s2_set_guild_member_role(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_target_user_id uuid,
  p_role text
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
  v_target_role text;
  v_officer_count integer;
begin
  if p_user_id is null or p_target_user_id is null
    or p_role is null or p_role not in ('officer', 'member')
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '역할 변경 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'setGuildMemberRole', 'expectedRevision', p_expected_revision,
    'targetUserId', p_target_user_id, 'role', p_role
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'setGuildMemberRole' then
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
      p_idempotency_key, 'FORBIDDEN', '부길드장 임명은 길드장만 할 수 있습니다.', v_revision, null, null
    );
  end if;

  select role into v_target_role
  from public.gacha_s2_guild_members
  where guild_id = v_guild_id and user_id = p_target_user_id;
  if v_target_role is null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '같은 길드의 길드원이 아닙니다.', v_revision, null, null
    );
  end if;
  if v_target_role = 'owner' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'FORBIDDEN', '길드장의 역할은 변경할 수 없습니다.', v_revision, null, null
    );
  end if;

  -- 부길드장은 최대 2명이다.
  if p_role = 'officer' and v_target_role <> 'officer' then
    select count(*) into v_officer_count
    from public.gacha_s2_guild_members where guild_id = v_guild_id and role = 'officer';
    if v_officer_count >= 2 then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'COMMAND_REJECTED', '부길드장은 최대 2명까지 임명할 수 있습니다.', v_revision, null, null
      );
    end if;
  end if;

  update public.gacha_s2_guild_members
  set role = p_role
  where guild_id = v_guild_id and user_id = p_target_user_id;

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'setGuildMemberRole', v_request_hash, v_revision,
    jsonb_build_object('guildId', v_guild_id, 'targetUserId', p_target_user_id, 'role', p_role)
  );
end;
$$;

revoke all on function public.gacha_s2_guild_apply_penalty(uuid, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_leave_guild(uuid, bigint, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_kick_guild_member(uuid, bigint, text, uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_set_guild_member_role(uuid, bigint, text, uuid, text) from public, anon, authenticated;

grant execute on function public.gacha_s2_leave_guild(uuid, bigint, text) to service_role;
grant execute on function public.gacha_s2_kick_guild_member(uuid, bigint, text, uuid) to service_role;
grant execute on function public.gacha_s2_set_guild_member_role(uuid, bigint, text, uuid, text) to service_role;
