-- 길드 M1 명령 RPC: 가입 신청 · 취소 · 승인/거절 (PDB-16)
--
-- 가입 처리는 길드의 join_mode 를 따른다.
--   approval : 신청을 쌓아 두고 길드장·부길드장이 승인/거절
--   auto     : 신청 즉시 가입 처리(정원 내에서만)
-- 탈퇴·추방 후 3일간은 어떤 길드에도 다시 들어갈 수 없다.

create or replace function public.gacha_s2_request_join_guild(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_guild_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_guild public.gacha_s2_guilds%rowtype;
  v_member_count integer;
  v_pending_count integer;
  v_penalty_until timestamptz;
  v_joined boolean := false;
begin
  if p_user_id is null or p_guild_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '가입 신청 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'requestJoinGuild', 'expectedRevision', p_expected_revision, 'guildId', p_guild_id
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'requestJoinGuild' then
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

  if exists (select 1 from public.gacha_s2_guild_membership(p_user_id)) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이미 소속된 길드가 있습니다.', v_revision, null, null
    );
  end if;

  select penalty_until into v_penalty_until
  from public.gacha_s2_guild_leave_penalties
  where user_id = p_user_id and penalty_until > now();
  if v_penalty_until is not null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '길드 탈퇴 후 3일 동안은 다시 가입할 수 없습니다.',
      v_revision, null, jsonb_build_object('penaltyUntil', floor(extract(epoch from v_penalty_until) * 1000)::bigint)
    );
  end if;

  select * into v_guild from public.gacha_s2_guilds
  where guild_id = p_guild_id and disbanded_at is null
  for update;
  if not found then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '존재하지 않는 길드입니다.', v_revision, null, null
    );
  end if;

  select count(*) into v_member_count
  from public.gacha_s2_guild_members where guild_id = p_guild_id;
  if v_member_count >= v_guild.member_limit then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '길드 정원이 가득 찼습니다.', v_revision, null, null
    );
  end if;

  if v_guild.join_mode = 'auto' then
    -- 자동 승인: 신청 기록을 남기되 즉시 가입시킨다.
    insert into public.gacha_s2_guild_members (guild_id, user_id, role)
    values (p_guild_id, p_user_id, 'member');

    insert into public.gacha_s2_guild_join_requests (guild_id, user_id, status, resolved_at, resolved_by)
    values (p_guild_id, p_user_id, 'approved', now(), p_user_id)
    on conflict (guild_id, user_id) do update
    set status = 'approved', requested_at = now(), resolved_at = now(), resolved_by = p_user_id;

    -- 가입이 확정됐으므로 다른 길드에 낸 신청은 정리한다.
    update public.gacha_s2_guild_join_requests
    set status = 'cancelled', resolved_at = now(), resolved_by = p_user_id
    where user_id = p_user_id and status = 'pending' and guild_id <> p_guild_id;

    v_joined := true;
  else
    -- 승인제: 동시 신청은 3개까지만 허용한다.
    select count(*) into v_pending_count
    from public.gacha_s2_guild_join_requests r
    join public.gacha_s2_guilds g on g.guild_id = r.guild_id
    where r.user_id = p_user_id and r.status = 'pending' and g.disbanded_at is null;

    if v_pending_count >= 3 and not exists (
      select 1 from public.gacha_s2_guild_join_requests
      where guild_id = p_guild_id and user_id = p_user_id and status = 'pending'
    ) then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'COMMAND_REJECTED', '가입 신청은 최대 3개까지 가능합니다.', v_revision, null, null
      );
    end if;

    insert into public.gacha_s2_guild_join_requests (guild_id, user_id, status)
    values (p_guild_id, p_user_id, 'pending')
    on conflict (guild_id, user_id) do update
    set status = 'pending', requested_at = now(), resolved_at = null, resolved_by = null;
  end if;

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'requestJoinGuild', v_request_hash, v_revision,
    jsonb_build_object('guildId', p_guild_id, 'joined', v_joined)
  );
end;
$$;

create or replace function public.gacha_s2_cancel_join_request(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_guild_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
begin
  if p_user_id is null or p_guild_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '신청 취소 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'cancelJoinRequest', 'expectedRevision', p_expected_revision, 'guildId', p_guild_id
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'cancelJoinRequest' then
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

  update public.gacha_s2_guild_join_requests
  set status = 'cancelled', resolved_at = now(), resolved_by = p_user_id
  where guild_id = p_guild_id and user_id = p_user_id and status = 'pending';

  if not found then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '대기 중인 가입 신청이 없습니다.', v_revision, null, null
    );
  end if;

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'cancelJoinRequest', v_request_hash, v_revision,
    jsonb_build_object('guildId', p_guild_id)
  );
end;
$$;

create or replace function public.gacha_s2_resolve_join_request(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_target_user_id uuid,
  p_approve boolean
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
  v_member_limit integer;
  v_member_count integer;
  v_penalty_until timestamptz;
begin
  if p_user_id is null or p_target_user_id is null or p_approve is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '가입 처리 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'resolveJoinRequest', 'expectedRevision', p_expected_revision,
    'targetUserId', p_target_user_id, 'approve', p_approve
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'resolveJoinRequest' then
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
      p_idempotency_key, 'FORBIDDEN', '가입 신청을 처리할 권한이 없습니다.', v_revision, null, null
    );
  end if;

  if not exists (
    select 1 from public.gacha_s2_guild_join_requests
    where guild_id = v_guild_id and user_id = p_target_user_id and status = 'pending'
  ) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '대기 중인 가입 신청이 아닙니다.', v_revision, null, null
    );
  end if;

  if not p_approve then
    update public.gacha_s2_guild_join_requests
    set status = 'rejected', resolved_at = now(), resolved_by = p_user_id
    where guild_id = v_guild_id and user_id = p_target_user_id;

    return public.gacha_s2_guild_command_ok(
      p_user_id, p_idempotency_key, 'resolveJoinRequest', v_request_hash, v_revision,
      jsonb_build_object('guildId', v_guild_id, 'targetUserId', p_target_user_id, 'approved', false)
    );
  end if;

  -- 승인 처리: 신청 이후에 상황이 바뀌었을 수 있으므로 다시 확인한다.
  if exists (select 1 from public.gacha_s2_guild_membership(p_target_user_id)) then
    update public.gacha_s2_guild_join_requests
    set status = 'cancelled', resolved_at = now(), resolved_by = p_user_id
    where guild_id = v_guild_id and user_id = p_target_user_id;
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이미 다른 길드에 가입한 유저입니다.', v_revision, null, null
    );
  end if;

  select penalty_until into v_penalty_until
  from public.gacha_s2_guild_leave_penalties
  where user_id = p_target_user_id and penalty_until > now();
  if v_penalty_until is not null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '탈퇴 페널티가 남아 있어 가입시킬 수 없습니다.', v_revision, null, null
    );
  end if;

  select member_limit into v_member_limit from public.gacha_s2_guilds where guild_id = v_guild_id for update;
  select count(*) into v_member_count from public.gacha_s2_guild_members where guild_id = v_guild_id;
  if v_member_count >= v_member_limit then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '길드 정원이 가득 찼습니다.', v_revision, null, null
    );
  end if;

  insert into public.gacha_s2_guild_members (guild_id, user_id, role)
  values (v_guild_id, p_target_user_id, 'member');

  update public.gacha_s2_guild_join_requests
  set status = 'approved', resolved_at = now(), resolved_by = p_user_id
  where guild_id = v_guild_id and user_id = p_target_user_id;

  update public.gacha_s2_guild_join_requests
  set status = 'cancelled', resolved_at = now(), resolved_by = p_user_id
  where user_id = p_target_user_id and status = 'pending' and guild_id <> v_guild_id;

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'resolveJoinRequest', v_request_hash, v_revision,
    jsonb_build_object('guildId', v_guild_id, 'targetUserId', p_target_user_id, 'approved', true)
  );
end;
$$;

revoke all on function public.gacha_s2_request_join_guild(uuid, bigint, text, uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_cancel_join_request(uuid, bigint, text, uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_resolve_join_request(uuid, bigint, text, uuid, boolean) from public, anon, authenticated;

grant execute on function public.gacha_s2_request_join_guild(uuid, bigint, text, uuid) to service_role;
grant execute on function public.gacha_s2_cancel_join_request(uuid, bigint, text, uuid) to service_role;
grant execute on function public.gacha_s2_resolve_join_request(uuid, bigint, text, uuid, boolean) to service_role;
