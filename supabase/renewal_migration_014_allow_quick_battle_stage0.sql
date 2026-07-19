-- Card Gacha Season 2: Allow Quick Battle at Stage 0
-- By user request, allow users to perform a quick battle even if they haven't cleared stage 1 yet (stage 0).
-- The reward will naturally be 0 points and 0 EXP due to the multiplication by 0, but it will not throw an error.

create or replace function public.gacha_s2_claim_quick_battle(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_verified_cleared_stages integer,
  p_verification_digest text
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
  v_quick jsonb;
  v_adventure_runs jsonb;
  v_support_items jsonb;
  v_active_buffs jsonb;
  v_cleared_stage integer;
  v_ex_claims jsonb;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_config jsonb;
  v_balance_version text;
  v_formation jsonb;
  v_now_ms bigint := public.gacha_s2_now_ms();
  v_interval_ms bigint;
  v_recovered integer;
  v_quick_count integer;
  v_quick_window_started bigint;
  v_quick_window_ms bigint;
  v_window_started bigint;
  v_run_count integer;
  v_window_ms bigint;
  v_seed bigint;
  v_points integer;
  v_card_exp integer;
  v_bonus_item text;
  v_highest integer;
  v_ex_result jsonb;
  v_run_id uuid := gen_random_uuid();
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_verified_cleared_stages is null or p_verified_cleared_stages not between 0 and 50
    or p_verification_digest is null or p_verification_digest !~ '^[0-9a-fA-F]{64}$' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '빠른 전투 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'claimQuickBattle', 'expectedRevision', p_expected_revision,
    'verifiedClearedStages', p_verified_cleared_stages,
    'verificationDigest', lower(p_verification_digest)
  )::text, 'sha256'), 'hex');
  select revision, action_energy, max_action_energy, last_energy_at, quick_battle,
    adventure_runs, support_items, active_buffs, cleared_stage, ex_milestone_claims
  into v_revision, v_energy, v_max_energy, v_last_energy_at, v_quick,
    v_adventure_runs, v_support_items, v_active_buffs, v_cleared_stage, v_ex_claims
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
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'claimQuickBattle' then
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
    select 1 from public.gacha_s2_adventure_runs
    where user_id = p_user_id and status = 'active'
  ) then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '진행 중인 모험 런을 먼저 정산해야 합니다.', v_revision, null, null);
  end if;
  select version, config into v_balance_version, v_config
  from public.gacha_s2_balance_versions where active;
  v_formation := public.gacha_s2_formation_snapshot(p_user_id);
  if v_config is null or v_formation is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '전투 카드 5장 편성이 필요합니다.', v_revision, null, null);
  end if;

  v_interval_ms := (v_config->'rewardRules'->>'energyRecoveryMinutes')::bigint * 60000;
  if v_energy < v_max_energy then
    v_recovered := floor(greatest(0, extract(epoch from (now() - v_last_energy_at)) * 1000) / v_interval_ms)::integer;
    v_energy := least(v_max_energy, v_energy + v_recovered);
  end if;
  if v_energy < (v_config->'rewardRules'->>'quickBattleEnergy')::integer then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '행동력이 부족합니다.', v_revision, null, null);
  end if;
  v_quick_window_ms := (v_config->'adventureRules'->>'runWindowMs')::bigint;
  v_quick_window_started := greatest(0, coalesce((v_quick->>'windowStartedAt')::bigint, 0));
  v_quick_count := greatest(0, coalesce((v_quick->>'count')::integer, 0));
  if v_quick_window_started = 0 or v_now_ms < v_quick_window_started or v_now_ms - v_quick_window_started >= v_quick_window_ms then
    v_quick_window_started := v_now_ms;
    v_quick_count := 0;
  end if;
  if v_quick_count >= (v_config->'rewardRules'->>'quickBattleDailyLimit')::integer then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '4시간당 빠른 전투 횟수를 모두 사용했습니다.', v_revision, null, null);
  end if;
  v_window_ms := (v_config->'adventureRules'->>'runWindowMs')::bigint;
  v_window_started := greatest(0, coalesce((v_adventure_runs->>'windowStartedAt')::bigint, 0));
  v_run_count := greatest(0, coalesce((v_adventure_runs->>'count')::integer, 0));
  if v_window_started = 0 or v_now_ms < v_window_started or v_now_ms - v_window_started >= v_window_ms then
    v_window_started := v_now_ms;
    v_run_count := 0;
  end if;
  if v_run_count >= (v_config->'adventureRules'->>'maxRunsPerWindow')::integer then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '4시간당 모험 횟수를 모두 사용했습니다.', v_revision, null, null);
  end if;

  v_seed := public.gacha_s2_new_seed();
  v_points := least(
    (v_config->'adventureRules'->'runReward'->>'maxPointsPerRun')::integer,
    p_verified_cleared_stages * (v_config->'adventureRules'->'runReward'->>'pointsBasePerStage')::integer
      + (v_config->'adventureRules'->'runReward'->>'pointsGrowthPerStage')::integer
        * p_verified_cleared_stages * (p_verified_cleared_stages + 1) / 2
  );
  v_card_exp := p_verified_cleared_stages
    * (v_config->'adventureRules'->'runReward'->>'cardExpPerClearedStage')::integer;
  if coalesce((v_active_buffs->>'cardExpEndAt')::bigint, 0) > v_now_ms then
    v_card_exp := ceil(v_card_exp * 1.5)::integer;
  end if;
  v_bonus_item := public.gacha_s2_roll_adventure_drop(v_config, p_verified_cleared_stages, v_seed, 10);
  if v_bonus_item is not null then
    v_support_items := jsonb_set(
      v_support_items, array[v_bonus_item],
      to_jsonb(coalesce((v_support_items->>v_bonus_item)::integer, 0) + 1), true
    );
  end if;
  v_highest := greatest(v_cleared_stage, p_verified_cleared_stages);
  v_ex_result := public.gacha_s2_grant_ex_milestones(p_user_id, v_highest, v_ex_claims, v_config);
  perform public.gacha_s2_grant_formation_exp(p_user_id, v_formation, v_card_exp, v_config);

  insert into public.gacha_s2_adventure_runs (
    run_id, user_id, start_command_id, finish_command_id, mode, status, balance_version,
    server_seed, formation_snapshot, verified_cleared_stages, verification_digest,
    reward_points, card_exp, bonus_item_id, ex_awards, finished_at
  ) values (
    v_run_id, p_user_id, p_idempotency_key, p_idempotency_key, 'quick',
    case when p_verified_cleared_stages = 50 then 'completed' else 'failed' end,
    v_balance_version, v_seed, v_formation, p_verified_cleared_stages, lower(p_verification_digest),
    v_points, v_card_exp, v_bonus_item, v_ex_result->'awards', now()
  );
  update public.gacha_s2_player_states
  set points = points + v_points,
      action_energy = v_energy - (v_config->'rewardRules'->>'quickBattleEnergy')::integer,
      last_energy_at = now(),
      quick_battle = jsonb_build_object('windowStartedAt', v_quick_window_started, 'count', v_quick_count + 1),
      adventure_runs = jsonb_build_object('windowStartedAt', v_window_started, 'count', v_run_count + 1),
      support_items = v_support_items,
      cleared_stage = v_highest,
      ex_milestone_claims = v_ex_result->'claims',
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
      'runId', v_run_id, 'mode', 'quick', 'clearedStages', p_verified_cleared_stages,
      'points', v_points, 'cardExp', v_card_exp,
      'bonusItemId', v_bonus_item, 'exAwards', v_ex_result->'awards',
      'verificationDigest', lower(p_verification_digest)
    )
  );
  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'claimQuickBattle', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'claimQuickBattle', v_request_hash, p_expected_revision, v_revision, v_seed
  );
  return v_response;
end;
$$;
