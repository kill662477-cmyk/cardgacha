-- Card Gacha Season 2: Fix minigame finish response contract mismatch
--
-- Restores the required `serverTime`, `serverSeed`, and `snapshot` keys in the
-- response JSON for `gacha_s2_command_finish_minigame`, which were accidentally
-- replaced with `timestamp` and `state` in migration 034, causing the client to
-- reject the successful response and display an error screen.

create or replace function public.gacha_s2_command_finish_minigame(
  p_idempotency_key text,
  p_run_id uuid,
  p_input_log jsonb,
  p_claimed_score integer
) returns jsonb
language plpgsql
volatile
as $$
declare
  v_user_id uuid := auth.uid();
  v_expected_revision bigint;
  v_revision bigint;
  v_request_hash text;
  v_previous record;
  v_run record;
  v_config jsonb;
  v_server_elapsed_ms bigint;
  v_verified jsonb;
  v_completed boolean;
  v_raw_reward integer;
  v_today date;
  v_daily_points integer;
  v_daily_cap integer;
  v_reward integer;
  v_input_digest text;
  v_snapshot jsonb;
  v_response jsonb;
begin
  v_expected_revision := (current_setting('request.headers', true)::jsonb->>'x-game-revision')::bigint;
  v_today := (current_setting('request.headers', true)::jsonb->>'x-game-date')::date;
  if v_expected_revision is null or v_today is null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '필수 헤더가 누락되었습니다.',
      p_expected_revision, null, null
    );
  end if;
  if jsonb_array_length(p_input_log) > 500 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '미니게임 입력 로그가 너무 깁니다.',
      p_expected_revision, null, null
    );
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'finishMinigame', 'expectedRevision', v_expected_revision,
    'runId', p_run_id, 'inputLog', p_input_log, 'claimedScore', p_claimed_score
  )::text, 'sha256'), 'hex');
  select revision into v_revision
  from public.gacha_s2_player_states
  where user_id = v_user_id
  for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;
  select * into v_previous
  from public.gacha_s2_idempotency
  where user_id = v_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'finishMinigame' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등성 키가 다른 요청에 사용되었습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;
  if v_expected_revision <> v_revision then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와야 합니다.',
      v_revision, public.gacha_s2_get_player_snapshot(v_user_id), null
    );
  end if;
  select * into v_run
  from public.gacha_s2_minigame_runs
  where run_id = p_run_id and user_id = v_user_id
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
  where user_id = v_user_id and play_date = v_run.play_date and game = v_run.game
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
  where user_id = v_user_id and play_date = v_run.play_date and game = v_run.game;
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
      mini_games = public.gacha_s2_minigame_state(v_user_id, v_today),
      revision = revision + 1,
      updated_at = now()
  where user_id = v_user_id;

  v_snapshot := public.gacha_s2_get_player_snapshot(v_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true,
    'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', (v_snapshot->>'revision')::bigint, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', v_run.server_seed,
    'snapshot', v_snapshot,
    'result', jsonb_build_object(
      'runId', p_run_id, 'game', v_run.game, 'difficulty', v_run.difficulty,
      'score', (v_verified->>'score')::integer, 'completed', v_completed,
      'rewardPoints', v_reward, 'dailyPointsEarned', v_daily_points + v_reward
    )
  );
  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response)
  values (v_user_id, p_idempotency_key, 'finishMinigame', v_request_hash, v_response);
  return v_response;
end;
$$;
