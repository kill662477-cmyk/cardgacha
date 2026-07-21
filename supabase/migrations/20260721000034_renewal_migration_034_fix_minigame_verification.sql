create or replace function public.gacha_s2_verify_memory_log(
  p_board jsonb,
  p_input_log jsonb,
  p_time_limit_seconds integer,
  p_server_elapsed_ms bigint
) returns jsonb
language plpgsql
immutable
strict
as $$
declare
  v_count integer := jsonb_array_length(p_board);
  v_active boolean[];
  v_action jsonb;
  v_start integer;
  v_end integer;
  v_at_ms bigint;
  v_previous_at bigint := 0;
  v_max_at bigint := least((p_time_limit_seconds::bigint + 15) * 1000, p_server_elapsed_ms + 10000);
  v_matches integer := 0;
  v_streak integer := 0;
  v_score integer := 0;
  v_valid_match boolean;
begin
  if v_count % 2 <> 0 or jsonb_array_length(p_input_log) > 500 then
    return jsonb_build_object('valid', false, 'reason', 'INVALID_LOG_SIZE');
  end if;
  v_active := array_fill(true, array[v_count]);
  for v_action in select value from jsonb_array_elements(p_input_log) loop
    if jsonb_typeof(v_action) <> 'object'
      or v_action->>'start' is null
      or v_action->>'end' is null
      or v_action->>'atMs' is null then
      return jsonb_build_object('valid', false, 'reason', 'INVALID_ACTION_FORMAT');
    end if;
    v_start := floor((v_action->>'start')::numeric)::integer;
    v_end := floor((v_action->>'end')::numeric)::integer;
    v_at_ms := floor((v_action->>'atMs')::numeric)::bigint;

    if v_start < 0 or v_start >= v_count or v_end < 0 or v_end >= v_count or v_start = v_end then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_BOUNDS');
    end if;
    if not v_active[v_start + 1] or not v_active[v_end + 1] then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_ALREADY_FLIPPED');
    end if;
    if v_at_ms < v_previous_at then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_TIME_BACKWARDS', 'atMs', v_at_ms, 'prevMs', v_previous_at);
    end if;
    if v_at_ms > v_max_at then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_TIME_EXCEEDED', 'atMs', v_at_ms, 'maxMs', v_max_at);
    end if;
    v_previous_at := v_at_ms;

    v_valid_match := (p_board->>v_start) = (p_board->>v_end);
    if v_valid_match then
      v_active[v_start + 1] := false;
      v_active[v_end + 1] := false;
      v_matches := v_matches + 1;
      v_streak := v_streak + 1;
      v_score := v_score + 100 + v_streak * 20;
    else
      v_streak := 0;
      v_score := greatest(0, v_score - 10);
    end if;
  end loop;
  return jsonb_build_object(
    'valid', true,
    'score', v_score,
    'completed', v_matches * 2 = v_count
  );
end;
$$;

create or replace function public.gacha_s2_verify_sum_ten_log(
  p_board jsonb,
  p_input_log jsonb,
  p_time_limit_seconds integer,
  p_server_elapsed_ms bigint
) returns jsonb
language plpgsql
immutable
strict
as $$
declare
  v_count integer := jsonb_array_length(p_board);
  v_active boolean[];
  v_values integer[];
  v_reshuffled integer[];
  v_action jsonb;
  v_start integer;
  v_end integer;
  v_at_ms bigint;
  v_previous_at bigint := 0;
  v_max_at bigint := least((p_time_limit_seconds::bigint + 15) * 1000, p_server_elapsed_ms + 10000);
  v_start_row integer;
  v_end_row integer;
  v_start_column integer;
  v_end_column integer;
  v_min_row integer;
  v_max_row integer;
  v_min_column integer;
  v_max_column integer;
  v_index integer;
  v_row integer;
  v_column integer;
  v_sum integer;
  v_score integer := 0;
  v_combinations integer := 0;
  v_valid_match boolean;
begin
  if v_count <> 170 or jsonb_array_length(p_input_log) > 500 then
    return jsonb_build_object('valid', false, 'reason', 'INVALID_LOG_SIZE');
  end if;
  v_active := array_fill(true, array[v_count]);
  v_values := array_fill(0, array[v_count]);
  for v_index in 0..(v_count - 1) loop
    v_values[v_index + 1] := (p_board->v_index->>'value')::integer;
  end loop;

  for v_action in select value from jsonb_array_elements(p_input_log) loop
    if jsonb_typeof(v_action) <> 'object'
      or v_action->>'start' is null
      or v_action->>'end' is null
      or v_action->>'atMs' is null then
      return jsonb_build_object('valid', false, 'reason', 'INVALID_ACTION_FORMAT');
    end if;
    v_start := floor((v_action->>'start')::numeric)::integer;
    v_end := floor((v_action->>'end')::numeric)::integer;
    v_at_ms := floor((v_action->>'atMs')::numeric)::bigint;

    if v_start < 0 or v_start >= v_count or v_end < 0 or v_end >= v_count or v_start = v_end then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_BOUNDS');
    end if;
    if v_at_ms < v_previous_at then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_TIME_BACKWARDS');
    end if;
    if v_at_ms > v_max_at then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_TIME_EXCEEDED');
    end if;
    v_previous_at := v_at_ms;

    v_start_row := v_start / 10;
    v_start_column := v_start % 10;
    v_end_row := v_end / 10;
    v_end_column := v_end % 10;
    v_min_row := least(v_start_row, v_end_row);
    v_max_row := greatest(v_start_row, v_end_row);
    v_min_column := least(v_start_column, v_end_column);
    v_max_column := greatest(v_start_column, v_end_column);

    v_sum := 0;
    v_valid_match := true;
    for v_row in v_min_row..v_max_row loop
      for v_column in v_min_column..v_max_column loop
        v_index := v_row * 10 + v_column;
        if v_active[v_index + 1] then
          v_sum := v_sum + v_values[v_index + 1];
        end if;
      end loop;
    end loop;

    if v_sum = 10 then
      for v_row in v_min_row..v_max_row loop
        for v_column in v_min_column..v_max_column loop
          v_index := v_row * 10 + v_column;
          if v_active[v_index + 1] then
            v_active[v_index + 1] := false;
            v_score := v_score + 1;
          end if;
        end loop;
      end loop;
      v_combinations := v_combinations + 1;
      
      v_reshuffled := public.gacha_s2_sum_ten_ensure_playable(v_active, v_values);
      if v_reshuffled is not null then
        v_values := v_reshuffled;
      end if;
    else
      return jsonb_build_object('valid', false, 'reason', 'INVALID_SUM_MATCH');
    end if;
  end loop;

  return jsonb_build_object(
    'valid', true,
    'score', v_score,
    'completed', v_score = v_count
  );
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
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등성 키가 다른 요청에 사용되었습니다.',
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
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '미니게임 진행을 찾을 수 없습니다.', v_revision, null, null);
  end if;
  if v_run.status <> 'active' or now() > v_run.expires_at + interval '15 seconds' then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '종료되었거나 만료된 미니게임 진입입니다.', v_revision, null, null);
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
      p_idempotency_key, 'COMMAND_REJECTED', '미니게임 입력 로그 검증에 실패했습니다. (사유: ' || coalesce(v_verified->>'reason', '알수없음') || ')',
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
  v_daily_cap := (v_config->'miniGameRules'->>'dailyPointCapPerGame')::integer;
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
  where user_id = p_user_id;

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true,
    'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', (v_snapshot->>'revision')::bigint, 'timestamp', (v_snapshot->>'updatedAt')::bigint,
    'result', jsonb_build_object(
      'runId', p_run_id, 'game', v_run.game, 'difficulty', v_run.difficulty,
      'score', (v_verified->>'score')::integer, 'completed', v_completed,
      'rewardPoints', v_reward, 'dailyPointsEarned', v_daily_points + v_reward
    ),
    'state', v_snapshot
  );
  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response)
  values (p_user_id, p_idempotency_key, 'finishMinigame', v_request_hash, v_response);
  return v_response;
end;
$$;
