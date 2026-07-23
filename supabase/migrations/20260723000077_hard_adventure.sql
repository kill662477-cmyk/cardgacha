-- Hard adventure 6-1 through 10-10 with mode-aware normal/quick rewards.
begin;

create or replace function public.gacha_s2_adventure_reward_points(
  p_config jsonb,
  p_mode text,
  p_cleared_stages integer
) returns integer
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v_cleared integer := greatest(0, least(50, coalesce(p_cleared_stages, 0)));
  v_reward jsonb;
begin
  if p_mode = 'hard' then
    if v_cleared = 0 then return 0; end if;
    v_reward := p_config->'adventureRules'->'hardRunReward';
    return (v_reward->>'minPointsPerRun')::integer
      + ((v_reward->>'maxPointsPerRun')::integer - (v_reward->>'minPointsPerRun')::integer)
        * (v_cleared - 1) / 49;
  end if;
  v_reward := p_config->'adventureRules'->'runReward';
  return least(
    (v_reward->>'maxPointsPerRun')::integer,
    floor(
      v_cleared * (v_reward->>'pointsBasePerStage')::numeric
      + (v_reward->>'pointsGrowthPerStage')::numeric * v_cleared * (v_cleared + 1) / 2
    )::integer
  );
end;
$$;

do $$
declare
  v_config jsonb;
  v_hash text;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active;
  if v_config is null then
    raise exception 'active balance config missing';
  end if;

  v_config := jsonb_set(v_config, '{balanceVersion}', '"2026.07.23-hard-adventure-1"'::jsonb, true);
  v_config := jsonb_set(v_config, '{rewardRules,maxStage}', '100'::jsonb, true);
  v_config := jsonb_set(v_config, '{adventureRules,modes}', '{
    "normal":{"label":"일반 모험","startStage":1,"endStage":50,"stageCount":50,"unlockStage":0},
    "hard":{"label":"하드 모험","startStage":51,"endStage":100,"stageCount":50,"unlockStage":50}
  }'::jsonb, true);
  v_config := jsonb_set(v_config, '{adventureRules,hardRunReward}', '{
    "minPointsPerRun":7000,"maxPointsPerRun":20000,"cardExpPerClearedStage":1
  }'::jsonb, true);
  v_hash := encode(digest(v_config::text, 'sha256'), 'hex');

  insert into public.gacha_s2_balance_versions(version, config, config_hash, catalog_hash, active)
  select
    '2026.07.23-hard-adventure-1',
    v_config,
    v_hash,
    catalog_hash,
    false
  from public.gacha_s2_balance_versions
  where active
  on conflict (version) do update
  set config = excluded.config,
      config_hash = excluded.config_hash,
      catalog_hash = excluded.catalog_hash,
      active = false;

  update public.gacha_s2_balance_versions
  set active = (version = '2026.07.23-hard-adventure-1');
end;
$$;

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
  v_global_cleared integer;
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
  if not found or v_run.mode not in ('normal','hard') or v_run.status <> 'active' then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '정산할 수 없는 모험 런입니다.', v_revision, null, null);
  end if;
  select config into v_config
  from public.gacha_s2_balance_versions
  where version = v_run.balance_version;
  if v_config is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '모험 밸런스 기록을 찾을 수 없습니다.', v_revision, null, null);
  end if;

  v_points := public.gacha_s2_adventure_reward_points(v_config, v_run.mode, v_run.verified_cleared_stages);
  v_card_exp := v_run.verified_cleared_stages
    * (case when v_run.mode = 'hard'
      then v_config->'adventureRules'->'hardRunReward'
      else v_config->'adventureRules'->'runReward'
    end->>'cardExpPerClearedStage')::integer;
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
  v_global_cleared := case
    when v_run.mode = 'hard' then 50 + v_run.verified_cleared_stages
    else v_run.verified_cleared_stages
  end;
  v_highest := greatest(v_cleared_stage, v_global_cleared);
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
      'runId', p_run_id, 'mode', v_run.mode,
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

do $$
declare
  v_constraint record;
begin
  for v_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public.gacha_s2_player_states'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%cleared_stage%'
  loop
    execute format('alter table public.gacha_s2_player_states drop constraint %I', v_constraint.conname);
  end loop;
end;
$$;
alter table public.gacha_s2_player_states
  add constraint gacha_s2_player_states_cleared_stage_hard_check
  check (cleared_stage between 0 and 100);

alter table public.gacha_s2_adventure_runs
  drop constraint if exists gacha_s2_adventure_runs_mode_check;
alter table public.gacha_s2_adventure_runs
  add constraint gacha_s2_adventure_runs_mode_check
  check (mode in ('normal','hard','quick','quick-hard'));

alter table public.gacha_s2_adventure_runs
  drop constraint if exists gacha_s2_adventure_runs_reward_points_check;
alter table public.gacha_s2_adventure_runs
  add constraint gacha_s2_adventure_runs_reward_points_check
  check (reward_points between 0 and 20000);

create or replace function public.gacha_s2_adventure_reward_points(
  p_config jsonb,
  p_mode text,
  p_cleared_stages integer
) returns integer
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v_cleared integer := greatest(0, least(50, coalesce(p_cleared_stages, 0)));
  v_reward jsonb;
begin
  if p_mode = 'hard' then
    if v_cleared = 0 then return 0; end if;
    v_reward := p_config->'adventureRules'->'hardRunReward';
    return (v_reward->>'minPointsPerRun')::integer
      + ((v_reward->>'maxPointsPerRun')::integer - (v_reward->>'minPointsPerRun')::integer)
        * (v_cleared - 1) / 49;
  end if;
  v_reward := p_config->'adventureRules'->'runReward';
  return least(
    (v_reward->>'maxPointsPerRun')::integer,
    floor(
      v_cleared * (v_reward->>'pointsBasePerStage')::numeric
      + (v_reward->>'pointsGrowthPerStage')::numeric * v_cleared * (v_cleared + 1) / 2
    )::integer
  );
end;
$$;

create or replace function public.gacha_s2_start_adventure_run(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_verified_cleared_stages integer,
  p_verification_digest text,
  p_mode text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_adventure_runs jsonb;
  v_cleared_stage integer;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_config jsonb;
  v_balance_version text;
  v_formation jsonb;
  v_now_ms bigint := public.gacha_s2_now_ms();
  v_window_started bigint;
  v_run_count integer;
  v_window_ms bigint;
  v_max_runs integer;
  v_start_stage integer;
  v_run_id uuid := gen_random_uuid();
  v_seed bigint;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_verified_cleared_stages is null or p_verified_cleared_stages not between 0 and 50
    or p_verification_digest is null or p_verification_digest !~ '^[0-9a-fA-F]{64}$'
    or p_mode not in ('normal','hard') then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '모험 시작 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'startAdventureRun', 'expectedRevision', p_expected_revision, 'mode', p_mode,
    'verifiedClearedStages', p_verified_cleared_stages,
    'verificationDigest', lower(p_verification_digest)
  )::text, 'sha256'), 'hex');

  select revision, adventure_runs, cleared_stage
  into v_revision, v_adventure_runs, v_cleared_stage
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
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'startAdventureRun' then
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
  if p_mode = 'hard' and v_cleared_stage < 50 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '일반 모험 5-10 클리어 후 하드 모험이 해금됩니다.', v_revision, null, null);
  end if;
  if exists (
    select 1 from public.gacha_s2_adventure_runs
    where user_id = p_user_id and status = 'active'
  ) then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '진행 중인 모험 런이 있습니다.', v_revision, null, null);
  end if;

  select version, config into v_balance_version, v_config
  from public.gacha_s2_balance_versions where active;
  v_formation := public.gacha_s2_formation_snapshot(p_user_id);
  if v_config is null or v_formation is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '전투 카드 5장 편성이 필요합니다.', v_revision, null, null);
  end if;
  v_window_ms := (v_config->'adventureRules'->>'runWindowMs')::bigint;
  v_max_runs := (v_config->'adventureRules'->>'maxRunsPerWindow')::integer;
  v_window_started := greatest(0, coalesce((v_adventure_runs->>'windowStartedAt')::bigint, 0));
  v_run_count := greatest(0, coalesce((v_adventure_runs->>'count')::integer, 0));
  if v_window_started = 0 or v_now_ms < v_window_started or v_now_ms - v_window_started >= v_window_ms then
    v_window_started := 0;
    v_run_count := 0;
  end if;
  if v_run_count >= v_max_runs then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '4시간당 모험 횟수를 모두 사용했습니다.', v_revision, null, null);
  end if;
  if v_window_started = 0 then v_window_started := v_now_ms; end if;
  v_start_stage := case when p_mode = 'hard' then 51 else 1 end;
  v_seed := public.gacha_s2_new_seed();

  insert into public.gacha_s2_adventure_runs (
    run_id, user_id, start_command_id, mode, status, balance_version, server_seed,
    formation_snapshot, verified_cleared_stages, verification_digest
  ) values (
    v_run_id, p_user_id, p_idempotency_key, p_mode, 'active', v_balance_version, v_seed,
    v_formation, p_verified_cleared_stages, lower(p_verification_digest)
  );
  update public.gacha_s2_player_states
  set adventure_runs = jsonb_build_object('windowStartedAt', v_window_started, 'count', v_run_count + 1),
      adventure_run = jsonb_build_object(
        'active', true, 'mode', p_mode, 'currentStage', v_start_stage, 'clearedStages', 0,
        'startedAt', v_now_ms, 'runId', v_run_id::text
      ),
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
      'runId', v_run_id, 'mode', p_mode,
      'verifiedClearedStages', p_verified_cleared_stages,
      'verificationDigest', lower(p_verification_digest),
      'formation', v_formation
    )
  );
  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'startAdventureRun', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'startAdventureRun', v_request_hash, p_expected_revision, v_revision, v_seed
  );
  return v_response;
end;
$$;

create or replace function public.gacha_s2_claim_quick_battle(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_verified_cleared_stages integer,
  p_verification_digest text,
  p_mode text
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
  v_window_started bigint;
  v_run_count integer;
  v_window_ms bigint;
  v_seed bigint;
  v_points integer;
  v_card_exp integer;
  v_bonus_item text;
  v_global_cleared integer;
  v_highest integer;
  v_ex_result jsonb;
  v_run_id uuid := gen_random_uuid();
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_verified_cleared_stages is null or p_verified_cleared_stages not between 1 and 50
    or p_verification_digest is null or p_verification_digest !~ '^[0-9a-fA-F]{64}$'
    or p_mode not in ('normal','hard') then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '빠른 전투 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'claimQuickBattle', 'expectedRevision', p_expected_revision, 'mode', p_mode,
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
  if p_mode = 'hard' and v_cleared_stage < 50 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '일반 모험 5-10 클리어 후 하드 모험이 해금됩니다.', v_revision, null, null);
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

  v_quick_window_started := greatest(0, coalesce((v_quick->>'windowStartedAt')::bigint, 0));
  v_quick_count := greatest(0, coalesce((v_quick->>'count')::integer, 0));
  v_window_ms := (v_config->'adventureRules'->>'runWindowMs')::bigint;
  if v_quick_window_started = 0 or v_now_ms < v_quick_window_started
    or v_now_ms - v_quick_window_started >= v_window_ms then
    v_quick_window_started := v_now_ms;
    v_quick_count := 0;
  end if;
  if v_quick_count >= (v_config->'rewardRules'->>'quickBattleDailyLimit')::integer then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '빠른 전투 횟수를 모두 사용했습니다.', v_revision, null, null);
  end if;

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
  v_points := public.gacha_s2_adventure_reward_points(v_config, p_mode, p_verified_cleared_stages);
  v_card_exp := p_verified_cleared_stages
    * (case when p_mode = 'hard'
      then v_config->'adventureRules'->'hardRunReward'
      else v_config->'adventureRules'->'runReward'
    end->>'cardExpPerClearedStage')::integer;
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
  v_global_cleared := case when p_mode = 'hard' then 50 + p_verified_cleared_stages else p_verified_cleared_stages end;
  v_highest := greatest(v_cleared_stage, v_global_cleared);
  v_ex_result := public.gacha_s2_grant_ex_milestones(p_user_id, v_highest, v_ex_claims, v_config);
  perform public.gacha_s2_grant_formation_exp(p_user_id, v_formation, v_card_exp, v_config);

  insert into public.gacha_s2_adventure_runs (
    run_id, user_id, start_command_id, finish_command_id, mode, status, balance_version,
    server_seed, formation_snapshot, verified_cleared_stages, verification_digest,
    reward_points, card_exp, bonus_item_id, ex_awards, finished_at
  ) values (
    v_run_id, p_user_id, p_idempotency_key, p_idempotency_key,
    case when p_mode = 'hard' then 'quick-hard' else 'quick' end,
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
      'runId', v_run_id, 'mode', 'quick', 'adventureMode', p_mode,
      'clearedStages', p_verified_cleared_stages,
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

revoke all on function public.gacha_s2_adventure_reward_points(jsonb, text, integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_start_adventure_run(uuid, bigint, text, integer, text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_claim_quick_battle(uuid, bigint, text, integer, text, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_start_adventure_run(uuid, bigint, text, integer, text, text) to service_role;
grant execute on function public.gacha_s2_claim_quick_battle(uuid, bigint, text, integer, text, text) to service_role;

do $$
declare
  v_active text;
begin
  select version into v_active from public.gacha_s2_balance_versions where active;
  if v_active <> '2026.07.23-hard-adventure-1' then
    raise exception 'hard adventure balance activation failed: %', coalesce(v_active, 'none');
  end if;
  if public.gacha_s2_adventure_reward_points(
    (select config from public.gacha_s2_balance_versions where active), 'hard', 1
  ) <> 7000 then
    raise exception 'hard adventure minimum reward validation failed';
  end if;
  if public.gacha_s2_adventure_reward_points(
    (select config from public.gacha_s2_balance_versions where active), 'hard', 50
  ) <> 20000 then
    raise exception 'hard adventure maximum reward validation failed';
  end if;
end;
$$;

commit;
