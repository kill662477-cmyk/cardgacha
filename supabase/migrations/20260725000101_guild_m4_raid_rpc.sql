-- 길드 M4: 레이드 공격 · 보상 · 조회 RPC (PDB-16 3.3)
--
-- 딜은 서버가 재현 검증한 값(p_verified_damage)만 받는다. 월드보스와 동일하게
-- 클라이언트가 보낸 수치를 그대로 믿지 않는다.

create or replace function public.gacha_s2_attack_guild_raid(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_verified_damage bigint,
  p_verification_digest text
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
  v_raid public.gacha_s2_guild_raids%rowtype;
  v_player public.gacha_s2_guild_raid_players%rowtype;
  v_now timestamptz := now();
  v_next_hp bigint;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_verified_damage is null or p_verified_damage < 0 or p_verified_damage > 1000000000
    or p_verification_digest is null or p_verification_digest !~ '^[0-9a-f]{64}$' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '레이드 공격 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'attackGuildRaid', 'expectedRevision', p_expected_revision, 'digest', p_verification_digest
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'attackGuildRaid' then
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

  select gm.guild_id into v_guild_id from public.gacha_s2_guild_membership(p_user_id) gm;
  if v_guild_id is null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '소속된 길드가 없습니다.', v_revision, null, null
    );
  end if;

  v_raid := public.gacha_s2_ensure_guild_raid(v_guild_id, v_now);
  if v_raid.raid_id is null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '지금은 길드 레이드 시간이 아닙니다.', v_revision, null, null
    );
  end if;

  select * into v_raid from public.gacha_s2_guild_raids where raid_id = v_raid.raid_id for update;

  if v_now >= v_raid.raid_ends_at then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '레이드 전투가 종료되었습니다.', v_revision, null, null
    );
  end if;
  if v_raid.current_hp = 0 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이미 처치된 레이드입니다.', v_revision, null, null
    );
  end if;

  select * into v_player from public.gacha_s2_guild_raid_players
  where raid_id = v_raid.raid_id and user_id = p_user_id for update;
  if not found then
    -- 회차 시작 이후 가입한 길드원. 이번 회차 보상 대상이 아니므로 공격도 막는다.
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이번 회차 참여 대상이 아닙니다. 다음 회차부터 참여할 수 있습니다.',
      v_revision, null, null
    );
  end if;
  if v_player.attempts >= 3 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이번 회차 공격 횟수를 모두 사용했습니다.', v_revision, null, null
    );
  end if;

  v_next_hp := greatest(0, v_raid.current_hp - p_verified_damage);

  update public.gacha_s2_guild_raids
  set current_hp = v_next_hp,
      player_damage = player_damage + p_verified_damage,
      defeated_at = case when v_next_hp = 0 then coalesce(defeated_at, v_now) else defeated_at end,
      updated_at = now()
  where raid_id = v_raid.raid_id;

  update public.gacha_s2_guild_raid_players
  set attempts = attempts + 1,
      total_damage = total_damage + p_verified_damage,
      best_damage = greatest(best_damage, p_verified_damage)
  where raid_id = v_raid.raid_id and user_id = p_user_id;

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'attackGuildRaid', v_request_hash, v_revision,
    jsonb_build_object(
      'raidId', v_raid.raid_id,
      'damage', p_verified_damage,
      'currentHp', v_next_hp,
      'maxHp', v_raid.max_hp,
      'defeated', v_next_hp = 0,
      'attempts', v_player.attempts + 1
    )
  );
end;
$$;

create or replace function public.gacha_s2_claim_guild_raid_reward(
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
  v_raid public.gacha_s2_guild_raids%rowtype;
  v_player public.gacha_s2_guild_raid_players%rowtype;
  v_now timestamptz := now();
  v_defeated boolean;
  v_points integer;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '레이드 보상 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'claimGuildRaidReward', 'expectedRevision', p_expected_revision
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'claimGuildRaidReward' then
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

  select gm.guild_id into v_guild_id from public.gacha_s2_guild_membership(p_user_id) gm;
  if v_guild_id is null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '소속된 길드가 없습니다.', v_revision, null, null
    );
  end if;

  -- 결과 창에서만 수령할 수 있다.
  select * into v_raid from public.gacha_s2_guild_raids
  where guild_id = v_guild_id and v_now >= raid_ends_at and v_now < ends_at
  order by starts_at desc limit 1;
  if not found then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '보상 수령 시간이 아닙니다.', v_revision, null, null
    );
  end if;

  select * into v_player from public.gacha_s2_guild_raid_players
  where raid_id = v_raid.raid_id and user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이번 회차 보상 대상이 아닙니다.', v_revision, null, null
    );
  end if;
  if v_player.claimed_at is not null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이미 보상을 받았습니다.', v_revision, null, null
    );
  end if;

  v_defeated := v_raid.current_hp = 0;

  -- 처치 성공: 참여 여부와 무관하게 전원 지급.
  -- 실패: 실제로 공격한 사람만 위로 보상.
  if v_defeated then
    v_points := 50000;
  elsif v_player.attempts > 0 then
    v_points := 15000;
  else
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '레이드에 실패했고 참여 기록이 없어 받을 보상이 없습니다.',
      v_revision, null, null
    );
  end if;

  update public.gacha_s2_guild_raid_players
  set claimed_at = v_now, reward_points = v_points
  where raid_id = v_raid.raid_id and user_id = p_user_id;

  update public.gacha_s2_player_states
  set points = points + v_points
  where user_id = p_user_id;

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'claimGuildRaidReward', v_request_hash, v_revision,
    jsonb_build_object(
      'raidId', v_raid.raid_id, 'defeated', v_defeated,
      'points', v_points, 'participated', v_player.attempts > 0
    )
  );
end;
$$;

-- 레이드 현황. 진행 중에는 실시간 참여 상황을, 종료 후에는 미참여자를 포함한
-- 전체 명단을 보여 준다(PDB-16 3.3 참여자 현황 공개).
create or replace function public.gacha_s2_get_guild_raid_status(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_guild_id uuid;
  v_raid public.gacha_s2_guild_raids%rowtype;
  v_now timestamptz := now();
  v_slot timestamptz;
begin
  select gm.guild_id into v_guild_id from public.gacha_s2_guild_membership(p_user_id) gm;
  if v_guild_id is null then return jsonb_build_object('active', false, 'raid', null); end if;

  v_slot := public.gacha_s2_guild_raid_current_slot(v_now);
  select * into v_raid from public.gacha_s2_guild_raids
  where guild_id = v_guild_id and (v_slot is null or starts_at = v_slot)
  order by starts_at desc limit 1;

  if v_raid.raid_id is null then
    return jsonb_build_object('active', false, 'raid', null, 'nextSlot', null);
  end if;

  return jsonb_build_object(
    'active', v_now >= v_raid.starts_at and v_now < v_raid.raid_ends_at and v_raid.current_hp > 0,
    'resultsOpen', v_now >= v_raid.raid_ends_at and v_now < v_raid.ends_at,
    'raid', jsonb_build_object(
      'raidId', v_raid.raid_id,
      'startsAt', floor(extract(epoch from v_raid.starts_at) * 1000)::bigint,
      'raidEndsAt', floor(extract(epoch from v_raid.raid_ends_at) * 1000)::bigint,
      'endsAt', floor(extract(epoch from v_raid.ends_at) * 1000)::bigint,
      'maxHp', v_raid.max_hp,
      'currentHp', v_raid.current_hp,
      'playerDamage', v_raid.player_damage,
      'activeMemberCount', v_raid.active_member_count,
      'defeated', v_raid.current_hp = 0
    ),
    'me', (
      select jsonb_build_object('attempts', p.attempts, 'totalDamage', p.total_damage,
        'claimed', p.claimed_at is not null, 'rewardPoints', p.reward_points)
      from public.gacha_s2_guild_raid_players p
      where p.raid_id = v_raid.raid_id and p.user_id = p_user_id
    ),
    -- 미참여자도 포함해야 누가 빠졌는지 알 수 있다.
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', p.user_id, 'nickname', a.nickname,
        'attempts', p.attempts, 'totalDamage', p.total_damage,
        'claimed', p.claimed_at is not null
      ) order by p.total_damage desc, a.nickname)
      from public.gacha_s2_guild_raid_players p
      join public.gacha_s2_accounts a on a.id = p.user_id
      where p.raid_id = v_raid.raid_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.gacha_s2_attack_guild_raid(uuid, bigint, text, bigint, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_claim_guild_raid_reward(uuid, bigint, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_get_guild_raid_status(uuid) from public, anon, authenticated;
grant execute on function public.gacha_s2_attack_guild_raid(uuid, bigint, text, bigint, text) to service_role;
grant execute on function public.gacha_s2_claim_guild_raid_reward(uuid, bigint, text) to service_role;
grant execute on function public.gacha_s2_get_guild_raid_status(uuid) to service_role;
