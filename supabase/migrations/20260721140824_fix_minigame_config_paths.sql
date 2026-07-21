create or replace function public.gacha_s2_start_minigame(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_game text,
  p_difficulty text default null
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
  v_balance_version text;
  v_today date := timezone('Asia/Seoul', now())::date;
  v_daily_points integer := 0;
  v_interval_ms bigint;
  v_recovered integer;
  v_energy_cost integer;
  v_time_limit integer;
  v_pairs integer;
  v_seed bigint;
  v_board jsonb;
  v_run_id uuid := gen_random_uuid();
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_game is null or p_game not in ('memory','sumTen')
    or (p_game = 'memory' and (p_difficulty is null or p_difficulty not in ('basic','advanced')))
    or (p_game = 'sumTen' and p_difficulty is not null) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '미니게임 시작 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'startMinigame', 'expectedRevision', p_expected_revision,
    'game', p_game, 'difficulty', p_difficulty
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
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'startMinigame' then
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
  if exists (
    select 1 from public.gacha_s2_minigame_runs
    where user_id = p_user_id and status = 'active' and expires_at + interval '15 seconds' >= now()
  ) then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '진행 중인 보상 미니게임이 있습니다.', v_revision, null, null);
  end if;
  select version, config into v_balance_version, v_config
  from public.gacha_s2_balance_versions where active;
  if v_config is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '활성 미니게임 설정이 없습니다.', v_revision, null, null);
  end if;
  select points_earned into v_daily_points
  from public.gacha_s2_minigame_daily
  where user_id = p_user_id and play_date = v_today and game = p_game;
  v_daily_points := coalesce(v_daily_points, 0);
  if v_daily_points >= (v_config->'miniGameRules'->p_game->>'dailyPointCapPerGame')::integer then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '오늘 해당 미니게임 보상 한도에 도달했습니다.', v_revision, null, null);
  end if;
  v_interval_ms := (v_config->'rewardRules'->>'energyRecoveryMinutes')::bigint * 60000;
  if v_energy < v_max_energy then
    v_recovered := floor(greatest(0, extract(epoch from (now() - v_last_energy_at)) * 1000) / v_interval_ms)::integer;
    v_energy := least(v_max_energy, v_energy + v_recovered);
  end if;
  v_energy_cost := (v_config->'miniGameRules'->p_game->>'energyCost')::integer;
  if v_energy < v_energy_cost then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '행동력이 부족합니다.', v_revision, null, null);
  end if;

  if p_game = 'memory' then
    v_time_limit := (v_config->'miniGameRules'->'memory'->(p_difficulty)->>'timeLimit')::integer;
    v_pairs := (v_config->'miniGameRules'->'memory'->(p_difficulty)->>'pairs')::integer;
  else
    v_time_limit := (v_config->'miniGameRules'->'sumTen'->>'timeLimit')::integer;
  end if;
  if v_time_limit is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '미니게임 규칙을 찾을 수 없습니다.', v_revision, null, null);
  end if;
  v_seed := public.gacha_s2_new_seed();
  v_board := case
    when p_game = 'memory' then public.gacha_s2_memory_board(v_seed, v_pairs)
    else public.gacha_s2_sum_ten_board(v_seed)
  end;

  update public.gacha_s2_minigame_runs
  set status = 'expired', finished_at = now()
  where user_id = p_user_id and status = 'active' and expires_at + interval '15 seconds' < now();
  insert into public.gacha_s2_minigame_daily (user_id, play_date, game)
  values (p_user_id, v_today, p_game)
  on conflict (user_id, play_date, game) do nothing;
  insert into public.gacha_s2_minigame_runs (
    run_id, user_id, start_command_id, game, difficulty, status, play_date,
    balance_version, server_seed, board, time_limit_seconds, expires_at
  ) values (
    v_run_id, p_user_id, p_idempotency_key, p_game, p_difficulty, 'active', v_today,
    v_balance_version, v_seed, v_board, v_time_limit, now() + make_interval(secs => v_time_limit)
  );
  update public.gacha_s2_player_states
  set action_energy = v_energy - v_energy_cost,
      last_energy_at = now(),
      mini_games = public.gacha_s2_minigame_state(p_user_id, v_today),
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
      'runId', v_run_id, 'game', p_game, 'difficulty', p_difficulty,
      'timeLimit', v_time_limit, 'board', v_board
    )
  );
  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'startMinigame', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'startMinigame', v_request_hash, p_expected_revision, v_revision, v_seed
  );
  return v_response;
end;
$$;

create or replace function public.gacha_s2_finish_minigame(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_run_id uuid,
  p_input_log jsonb,
  p_claimed_score integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_run public.gacha_s2_minigame_runs%rowtype;
  v_config jsonb;
  v_verified jsonb;
  v_server_elapsed_ms bigint;
  v_daily_points integer;
  v_raw_reward integer;
  v_reward integer;
  v_daily_cap integer;
  v_completed boolean;
  v_input_digest text;
  v_today date := timezone('Asia/Seoul', now())::date;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null or p_run_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_input_log is null or jsonb_typeof(p_input_log) <> 'array'
    or p_claimed_score is null or p_claimed_score < 0 or p_claimed_score > 100000 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '미니게임 종료 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;
  if jsonb_array_length(p_input_log) > 500 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '미니게임 입력 로그가 너무 깁니다.',
      p_expected_revision, null, null
    );
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'finishMinigame', 'expectedRevision', p_expected_revision,
    'runId', p_run_id, 'inputLog', p_input_log, 'claimedScore', p_claimed_score
  )::text, 'sha256'), 'hex');
  select revision into v_revision
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
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'finishMinigame' then
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
  select * into v_run
  from public.gacha_s2_minigame_runs
  where run_id = p_run_id and user_id = p_user_id
  for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '미니게임 런을 찾을 수 없습니다.', v_revision, null, null);
  end if;
  if v_run.status <> 'active' or now() > v_run.expires_at + interval '15 seconds' then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '종료되었거나 만료된 미니게임 런입니다.', v_revision, null, null);
  end if;
  select config into v_config
  from public.gacha_s2_balance_versions
  where version = v_run.balance_version;
  if v_config is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '미니게임 밸런스 기록을 찾을 수 없습니다.', v_revision, null, null);
  end if;
  v_server_elapsed_ms := floor(extract(epoch from (now() - v_run.started_at)) * 1000)::bigint;
  v_verified := case
    when v_run.game = 'memory' then public.gacha_s2_verify_memory_log(
      v_run.board, p_input_log, v_run.time_limit_seconds, v_server_elapsed_ms
    )
    else public.gacha_s2_verify_sum_ten_log(
      v_run.board, p_input_log, v_run.time_limit_seconds, v_server_elapsed_ms
    )
  end;
  if coalesce((v_verified->>'valid')::boolean, false) is not true then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '미니게임 입력 로그 검증에 실패했습니다.',
      v_revision, null, v_verified
    );
  end if;
  if (v_verified->>'score')::integer <> p_claimed_score then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '제출 점수와 서버 재계산 점수가 일치하지 않습니다.',
      v_revision, null, v_verified
    );
  end if;
  v_completed := (v_verified->>'completed')::boolean;
  if v_run.game = 'memory' then
    v_raw_reward := case when v_completed then
      (v_config->'miniGameRules'->'memory'->(v_run.difficulty)->>'completionReward')::integer
    else 0 end;
  else
    v_raw_reward := case when p_claimed_score > 0 then least(
      (v_config->'miniGameRules'->'sumTen'->>'maxReward')::integer,
      (v_config->'miniGameRules'->'sumTen'->>'baseReward')::integer
        + floor(p_claimed_score * (v_config->'miniGameRules'->'sumTen'->>'rewardPerScore')::numeric)::integer
    ) else 0 end;
  end if;
  select points_earned into v_daily_points
  from public.gacha_s2_minigame_daily
  where user_id = p_user_id and play_date = v_run.play_date and game = v_run.game
  for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '미니게임 일일 기록을 찾을 수 없습니다.', v_revision, null, null);
  end if;
  v_daily_cap := (v_config->'miniGameRules'->v_run.game->>'dailyPointCapPerGame')::integer;
  v_reward := least(greatest(0, v_daily_cap - v_daily_points), v_raw_reward);
  v_input_digest := encode(digest(p_input_log::text, 'sha256'), 'hex');

  update public.gacha_s2_minigame_daily
  set points_earned = points_earned + v_reward,
      plays = plays + 1,
      best_score = greatest(best_score, p_claimed_score),
      updated_at = now()
  where user_id = p_user_id and play_date = v_run.play_date and game = v_run.game;
  update public.gacha_s2_minigame_runs
  set finish_command_id = p_idempotency_key,
      status = 'completed',
      input_log = p_input_log,
      input_digest = v_input_digest,
      claimed_score = p_claimed_score,
      verified_score = (v_verified->>'score')::integer,
      completed = v_completed,
      reward_points = v_reward,
      finished_at = now()
  where run_id = p_run_id;
  update public.gacha_s2_player_states
  set points = points + v_reward,
      mini_games = public.gacha_s2_minigame_state(p_user_id, v_today),
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id
  returning revision into v_revision;

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true,
    'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', v_run.server_seed,
    'snapshot', v_snapshot,
    'result', jsonb_build_object(
      'runId', p_run_id, 'game', v_run.game, 'difficulty', v_run.difficulty,
      'score', (v_verified->>'score')::integer, 'completed', v_completed,
      'rewardPoints', v_reward, 'inputDigest', v_input_digest,
      'verification', v_verified
    )
  );
  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'finishMinigame', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'finishMinigame', v_request_hash, p_expected_revision, v_revision, v_run.server_seed
  );
  return v_response;
end;
$$;