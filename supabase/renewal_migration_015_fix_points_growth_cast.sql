-- Card Gacha Season 2: Fix float cast error for pointsGrowthPerStage
-- pointsGrowthPerStage was changed to 5.5 in a balance patch, but the SQL was casting the extracted JSON value directly to ::integer
-- This caused a 'invalid input syntax for type integer: "5.5"' error, rolling back adventure run completion and quick battles.
-- We fix this by casting to ::numeric first, then casting the final calculated result to ::integer.

create or replace function public.gacha_s2_finish_adventure_run(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_run_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_support_items jsonb;
  v_active_buffs jsonb;
  v_cleared_stage integer;
  v_ex_claims jsonb;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_run public.gacha_s2_adventure_runs%rowtype;
  v_config jsonb;
  v_points integer;
  v_card_exp integer;
  v_bonus_item text;
  v_ex_result jsonb;
  v_highest integer;
  v_now_ms bigint := public.gacha_s2_now_ms();
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null or p_run_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '모험 정산 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'finishAdventureRun', 'expectedRevision', p_expected_revision, 'runId', p_run_id
  )::text, 'sha256'), 'hex');
  select revision, support_items, active_buffs, cleared_stage, ex_milestone_claims
  into v_revision, v_support_items, v_active_buffs, v_cleared_stage, v_ex_claims
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
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'finishAdventureRun' then
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
  from public.gacha_s2_adventure_runs
  where run_id = p_run_id and user_id = p_user_id
  for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '정산할 수 없는 모험 런입니다.', v_revision, null, null);
  end if;
  if v_run.mode <> 'normal' or v_run.status <> 'active' then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '정산할 수 없는 모험 런입니다.', v_revision, null, null);
  end if;
  select config into v_config
  from public.gacha_s2_balance_versions
  where version = v_run.balance_version;
  if v_config is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '모험 밸런스 기록을 찾을 수 없습니다.', v_revision, null, null);
  end if;

  v_points := least(
    (v_config->'adventureRules'->'runReward'->>'maxPointsPerRun')::integer,
    (v_run.verified_cleared_stages * (v_config->'adventureRules'->'runReward'->>'pointsBasePerStage')::integer
      + (v_config->'adventureRules'->'runReward'->>'pointsGrowthPerStage')::numeric
        * v_run.verified_cleared_stages * (v_run.verified_cleared_stages + 1) / 2)::integer
  );
  v_card_exp := v_run.verified_cleared_stages
    * (v_config->'adventureRules'->'runReward'->>'cardExpPerClearedStage')::integer;
  if coalesce((v_active_buffs->>'cardExpEndAt')::bigint, 0) > v_now_ms then
    v_card_exp := ceil(v_card_exp * 1.5)::integer;
  end if;
  v_bonus_item := public.gacha_s2_roll_adventure_drop(
    v_config, v_run.verified_cleared_stages, v_run.server_seed, 10
  );
  if v_bonus_item is not null then
    v_support_items := jsonb_set(
      v_support_items, array[v_bonus_item],
      to_jsonb(coalesce((v_support_items->>v_bonus_item)::integer, 0) + 1), true
    );
  end if;
  v_highest := greatest(v_cleared_stage, v_run.verified_cleared_stages);
  v_ex_result := public.gacha_s2_grant_ex_milestones(p_user_id, v_highest, v_ex_claims, v_config);
  perform public.gacha_s2_grant_formation_exp(p_user_id, v_run.formation_snapshot, v_card_exp, v_config);

  update public.gacha_s2_player_states
  set points = points + v_points,
      support_items = v_support_items,
      cleared_stage = v_highest,
      ex_milestone_claims = v_ex_result->'claims',
      adventure_run = '{"active":false,"currentStage":1,"clearedStages":0,"startedAt":0}'::jsonb,
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id
  returning revision into v_revision;
  update public.gacha_s2_adventure_runs
  set finish_command_id = p_idempotency_key,
      status = case when verified_cleared_stages = 50 then 'completed' else 'failed' end,
      reward_points = v_points,
      card_exp = v_card_exp,
      bonus_item_id = v_bonus_item,
      ex_awards = v_ex_result->'awards',
      finished_at = now()
  where run_id = p_run_id;

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true,
    'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', v_now_ms, 'serverSeed', v_run.server_seed,
    'snapshot', v_snapshot,
    'result', jsonb_build_object(
      'runId', p_run_id, 'mode', 'normal',
      'clearedStages', v_run.verified_cleared_stages,
      'points', v_points, 'cardExp', v_card_exp,
      'bonusItemId', v_bonus_item, 'exAwards', v_ex_result->'awards'
    )
  );
  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'finishAdventureRun', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'finishAdventureRun', v_request_hash, p_expected_revision, v_revision, v_run.server_seed
  );
  return v_response;
end;
$$;
