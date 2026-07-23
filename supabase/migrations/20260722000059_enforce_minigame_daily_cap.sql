-- Enforce the 3,000P per-game daily cap for ladder before charging energy.

begin;

update public.gacha_s2_minigame_daily
set points_earned = least(points_earned, 3000),
    updated_at = now()
where points_earned > 3000;

alter table public.gacha_s2_minigame_daily
  drop constraint if exists gacha_s2_minigame_daily_points_earned_check;
alter table public.gacha_s2_minigame_daily
  add constraint gacha_s2_minigame_daily_points_earned_check
  check (points_earned between 0 and 3000);

alter table public.gacha_s2_ladder_plays
  drop constraint if exists gacha_s2_ladder_plays_reward_points_check;
alter table public.gacha_s2_ladder_plays
  add constraint gacha_s2_ladder_plays_reward_points_check
  check (reward_points between 0 and 3000);

update public.gacha_s2_player_states as state
set mini_games = public.gacha_s2_minigame_state(
      state.user_id,
      timezone('Asia/Seoul', now())::date
    ),
    updated_at = now();

create or replace function public.gacha_s2_play_ladder(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_lane integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_energy integer;
  v_max_energy integer;
  v_last_energy_at timestamptz;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_config jsonb;
  v_ladder_rules jsonb;
  v_rewards jsonb;
  v_energy_cost integer;
  v_daily_cap integer;
  v_daily_points integer := 0;
  v_interval_ms bigint;
  v_recovered integer;
  v_seed bigint;
  v_reward_index integer;
  v_rolled_reward integer;
  v_reward integer;
  v_today date := timezone('Asia/Seoul', now())::date;
  v_now timestamptz := now();
  v_now_ms bigint := public.gacha_s2_now_ms();
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_lane is null or p_lane < 0 or p_lane > 5 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '사다리 출발점 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'playLadder', 'expectedRevision', p_expected_revision, 'lane', p_lane
  )::text, 'sha256'), 'hex');

  select revision, action_energy, max_action_energy, last_energy_at
  into v_revision, v_energy, v_max_energy, v_last_energy_at
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
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'playLadder' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등키를 다른 요청에 사용할 수 없습니다.',
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

  select config into v_config
  from public.gacha_s2_balance_versions
  where active;
  v_ladder_rules := v_config->'miniGameRules'->'ladder';
  v_rewards := v_ladder_rules->'rewards';
  v_energy_cost := (v_ladder_rules->>'energyCost')::integer;
  v_daily_cap := (v_config->'miniGameRules'->>'dailyPointCapPerGame')::integer;
  if v_ladder_rules is null
    or v_rewards is null
    or jsonb_typeof(v_rewards) <> 'array'
    or jsonb_array_length(v_rewards) <> 6
    or v_energy_cost is distinct from 100
    or v_daily_cap is distinct from 3000 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '사다리 보상 설정을 불러올 수 없습니다.', v_revision, null, null);
  end if;

  select points_earned into v_daily_points
  from public.gacha_s2_minigame_daily
  where user_id = p_user_id and play_date = v_today and game = 'ladder'
  for update;
  v_daily_points := coalesce(v_daily_points, 0);
  if v_daily_points >= v_daily_cap then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '오늘 운명의 사다리 보상 한도에 도달했습니다.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null
    );
  end if;

  v_interval_ms := (v_config->'rewardRules'->>'energyRecoveryMinutes')::bigint * 60000;
  if v_energy < v_max_energy then
    v_recovered := floor(greatest(0, extract(epoch from (v_now - v_last_energy_at)) * 1000) / v_interval_ms)::integer;
    v_energy := least(v_max_energy, v_energy + v_recovered);
  end if;
  if v_energy < v_energy_cost then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '행동력이 100 이상 필요합니다.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null
    );
  end if;

  v_seed := public.gacha_s2_new_seed();
  v_reward_index := least(5, floor(public.gacha_s2_seed_roll(v_seed, 0) * 6)::integer);
  v_rolled_reward := (v_rewards->>v_reward_index)::integer;
  v_reward := least(v_daily_cap - v_daily_points, v_rolled_reward);

  insert into public.gacha_s2_minigame_daily (
    user_id, play_date, game, points_earned, plays, best_score
  ) values (
    p_user_id, v_today, 'ladder', v_reward, 1, v_rolled_reward
  ) on conflict (user_id, play_date, game) do update
  set points_earned = public.gacha_s2_minigame_daily.points_earned + excluded.points_earned,
      plays = public.gacha_s2_minigame_daily.plays + 1,
      best_score = greatest(public.gacha_s2_minigame_daily.best_score, excluded.best_score),
      updated_at = now();

  insert into public.gacha_s2_ladder_plays (
    user_id, command_id, play_date, chosen_lane, reward_index, reward_points, server_seed
  ) values (
    p_user_id, p_idempotency_key, v_today, p_lane, v_reward_index, v_reward, v_seed
  );

  update public.gacha_s2_player_states
  set points = points + v_reward,
      action_energy = v_energy - v_energy_cost,
      last_energy_at = v_now,
      mini_games = public.gacha_s2_minigame_state(p_user_id, v_today),
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id
  returning revision into v_revision;

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true,
    'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', v_now_ms, 'serverSeed', v_seed,
    'snapshot', v_snapshot,
    'result', jsonb_build_object(
      'chosenLane', p_lane,
      'rewardIndex', v_reward_index,
      'rolledRewardPoints', v_rolled_reward,
      'rewardPoints', v_reward,
      'energyCost', v_energy_cost,
      'serverSeed', v_seed
    )
  );

  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'playLadder', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'playLadder', v_request_hash, p_expected_revision, v_revision, v_seed
  );
  return v_response;
end;
$$;

revoke all on function public.gacha_s2_play_ladder(uuid, bigint, text, integer) from public, anon, authenticated;
grant execute on function public.gacha_s2_play_ladder(uuid, bigint, text, integer) to service_role;

commit;
