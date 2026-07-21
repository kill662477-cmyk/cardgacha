-- Card Gacha Season 2: adventure verification and server-validated minigames.
-- REVIEW ONLY. Run after migrations 001-004. Service role only.

begin;

do $$
begin
  if to_regclass('public.gacha_s2_pack_draws') is null
    or to_regprocedure('public.gacha_s2_new_seed()') is null
    or to_regprocedure('public.gacha_s2_seed_roll(bigint,integer)') is null then
    raise exception 'missing Season 2 economy schema: run migrations 001-004 first';
  end if;
end;
$$;

create table if not exists public.gacha_s2_adventure_runs (
  run_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  start_command_id text not null,
  finish_command_id text,
  mode text not null check (mode in ('normal','quick')),
  status text not null check (status in ('active','completed','failed')),
  balance_version text not null references public.gacha_s2_balance_versions(version),
  server_seed bigint not null check (server_seed between 0 and 4294967295),
  formation_snapshot jsonb not null check (
    jsonb_typeof(formation_snapshot) = 'array' and jsonb_array_length(formation_snapshot) = 5
  ),
  verified_cleared_stages integer not null check (verified_cleared_stages between 0 and 50),
  verification_digest text not null check (verification_digest ~ '^[0-9a-fA-F]{64}$'),
  reward_points integer not null default 0 check (reward_points between 0 and 15000),
  card_exp integer not null default 0 check (card_exp >= 0),
  bonus_item_id text,
  ex_awards jsonb not null default '[]'::jsonb check (jsonb_typeof(ex_awards) = 'array'),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  unique (user_id, start_command_id),
  unique (user_id, finish_command_id)
);

create unique index if not exists idx_gacha_s2_adventure_one_active
  on public.gacha_s2_adventure_runs(user_id)
  where status = 'active';
create index if not exists idx_gacha_s2_adventure_user_started
  on public.gacha_s2_adventure_runs(user_id, started_at desc);

create table if not exists public.gacha_s2_minigame_daily (
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  play_date date not null,
  game text not null check (game in ('memory','sumTen')),
  points_earned integer not null default 0 check (points_earned between 0 and 5000),
  plays integer not null default 0 check (plays >= 0),
  best_score integer not null default 0 check (best_score >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, play_date, game)
);

create table if not exists public.gacha_s2_minigame_runs (
  run_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  start_command_id text not null,
  finish_command_id text,
  game text not null check (game in ('memory','sumTen')),
  difficulty text,
  status text not null check (status in ('active','completed','expired')),
  play_date date not null,
  balance_version text not null references public.gacha_s2_balance_versions(version),
  server_seed bigint not null check (server_seed between 0 and 4294967295),
  board jsonb not null check (jsonb_typeof(board) = 'array'),
  time_limit_seconds integer not null check (time_limit_seconds between 1 and 300),
  input_log jsonb check (input_log is null or jsonb_typeof(input_log) = 'array'),
  input_digest text check (input_digest is null or input_digest ~ '^[0-9a-fA-F]{64}$'),
  claimed_score integer check (claimed_score is null or claimed_score >= 0),
  verified_score integer check (verified_score is null or verified_score >= 0),
  completed boolean,
  reward_points integer not null default 0 check (reward_points between 0 and 1500),
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  finished_at timestamptz,
  unique (user_id, start_command_id),
  unique (user_id, finish_command_id),
  check (
    (game = 'memory' and difficulty in ('basic','advanced'))
    or (game = 'sumTen' and difficulty is null)
  )
);

create unique index if not exists idx_gacha_s2_minigame_one_active
  on public.gacha_s2_minigame_runs(user_id)
  where status = 'active';
create index if not exists idx_gacha_s2_minigame_user_started
  on public.gacha_s2_minigame_runs(user_id, started_at desc);

alter table public.gacha_s2_adventure_runs enable row level security;
alter table public.gacha_s2_minigame_daily enable row level security;
alter table public.gacha_s2_minigame_runs enable row level security;

create or replace function public.gacha_s2_get_player_snapshot(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'schemaVersion', s.schema_version,
    'revision', s.revision,
    'nickname', a.nickname,
    'actionEnergy', s.action_energy,
    'maxActionEnergy', s.max_action_energy,
    'lastEnergyAt', floor(extract(epoch from s.last_energy_at) * 1000)::bigint,
    'points', s.points,
    'clearedStage', s.cleared_stage,
    'pendingPoints', s.pending_points,
    'lastRewardAt', floor(extract(epoch from s.last_reward_at) * 1000)::bigint,
    'quickBattle', s.quick_battle,
    'adventureRuns', s.adventure_runs,
    'adventureRun', s.adventure_run || coalesce((
      select jsonb_build_object(
        'runId', run.run_id::text,
        'verifiedClearedStages', run.verified_cleared_stages,
        'verificationDigest', run.verification_digest
      )
      from public.gacha_s2_adventure_runs run
      where run.user_id = s.user_id and run.status = 'active'
      limit 1
    ), '{}'::jsonb),
    'cardProgress', coalesce((
      select jsonb_object_agg(c.card_id, jsonb_build_object('enhancement', c.enhancement, 'exp', c.card_exp))
      from public.gacha_s2_player_cards c where c.user_id = s.user_id
    ), '{}'::jsonb),
    'cardCopies', coalesce((
      select jsonb_object_agg(c.card_id, c.copies)
      from public.gacha_s2_player_cards c where c.user_id = s.user_id
    ), '{}'::jsonb),
    'cardLocks', coalesce((
      select jsonb_object_agg(c.card_id, c.locked)
      from public.gacha_s2_player_cards c where c.user_id = s.user_id
    ), '{}'::jsonb),
    'collectionRecords', coalesce((
      select jsonb_object_agg(r.card_id, true)
      from public.gacha_s2_collection_records r where r.user_id = s.user_id
    ), '{}'::jsonb),
    'supportItems', s.support_items,
    'activeBuffs', s.active_buffs,
    'shopTransactions', s.shop_transactions,
    'enhancementAttempts', s.enhancement_attempts,
    'miniGames', s.mini_games,
    'worldBoss', s.world_boss,
    'exMilestoneClaims', s.ex_milestone_claims,
    'representativeCardId', s.representative_card_id,
    'formation', to_jsonb(s.formation),
    'formationPresets', s.formation_presets,
    'activeFormationPresetId', s.active_formation_preset_id,
    'miniGameRuns', coalesce((
      select jsonb_agg(jsonb_build_object(
        'runId', run.run_id::text,
        'game', run.game,
        'difficulty', run.difficulty,
        'status', run.status,
        'seed', run.server_seed,
        'board', run.board,
        'timeLimit', run.time_limit_seconds,
        'startedAt', floor(extract(epoch from run.started_at) * 1000)::bigint,
        'expiresAt', floor(extract(epoch from run.expires_at) * 1000)::bigint
      ) order by run.started_at desc)
      from public.gacha_s2_minigame_runs run
      where run.user_id = s.user_id
        and run.status = 'active'
        and run.expires_at + interval '15 seconds' >= now()
    ), '[]'::jsonb),
    'powerRanking', jsonb_build_object(
      'seasonId', 'season-2',
      'snapshotAt', coalesce(floor(extract(epoch from s.power_snapshot_at) * 1000)::bigint, 0),
      'power', s.power_snapshot,
      'rank', null,
      'population', 0
    )
  )
  from public.gacha_s2_player_states s
  join public.gacha_s2_accounts a on a.id = s.user_id
  where s.user_id = p_user_id;
$$;

create or replace function public.gacha_s2_formation_snapshot(p_user_id uuid)
returns jsonb
language sql
stable
strict
as $$
  select case when count(*) = 5 and count(distinct catalog.card_id) = 5 then
    jsonb_agg(jsonb_build_object(
      'cardId', catalog.card_id,
      'rarity', catalog.rarity,
      'race', catalog.race,
      'archetype', catalog.archetype,
      'enhancement', owned.enhancement
    ) order by formation.ordinality)
  else null end
  from public.gacha_s2_player_states state
  cross join unnest(state.formation) with ordinality as formation(card_id, ordinality)
  join public.gacha_s2_player_cards owned
    on owned.user_id = state.user_id and owned.card_id = formation.card_id and owned.copies > 0
  join public.gacha_s2_card_catalog catalog
    on catalog.card_id = owned.card_id and catalog.rarity <> 'EX' and not catalog.is_group
  where state.user_id = p_user_id;
$$;

create or replace function public.gacha_s2_roll_adventure_drop(
  p_config jsonb,
  p_cleared_stages integer,
  p_seed bigint,
  p_counter integer default 0
) returns text
language plpgsql
immutable
strict
as $$
declare
  v_tier jsonb;
  v_weights jsonb;
  v_roll numeric;
  v_item_id text;
begin
  if p_cleared_stages < 1 then return null; end if;
  select tier into v_tier
  from jsonb_array_elements(p_config->'bonusDropRules'->'adventureTiers') as tiers(tier)
  where (tier->>'minClearedStages')::integer <= p_cleared_stages
  order by (tier->>'minClearedStages')::integer desc
  limit 1;
  if v_tier is null
    or public.gacha_s2_seed_roll(p_seed, p_counter) >= (v_tier->>'dropRate')::numeric then
    return null;
  end if;
  v_weights := case
    when public.gacha_s2_seed_roll(p_seed, p_counter + 1) < (v_tier->>'packShare')::numeric
      then p_config->'bonusDropRules'->'packWeights'
    else p_config->'bonusDropRules'->'itemWeights'
  end;
  v_roll := public.gacha_s2_seed_roll(p_seed, p_counter + 2);
  with weights as (
    select key as item_id, value::numeric as weight
    from jsonb_each_text(v_weights)
  ), weighted as (
    select item_id,
      sum(weight) over (order by item_id) as cumulative,
      sum(weight) over () as total
    from weights
  )
  select item_id into v_item_id
  from weighted
  where v_roll * total < cumulative
  order by cumulative
  limit 1;
  return v_item_id;
end;
$$;

create or replace function public.gacha_s2_grant_formation_exp(
  p_user_id uuid,
  p_formation jsonb,
  p_card_exp integer,
  p_config jsonb
) returns void
language plpgsql
as $$
declare
  v_card jsonb;
begin
  if p_card_exp <= 0 then return; end if;
  for v_card in select value from jsonb_array_elements(p_formation) loop
    update public.gacha_s2_player_cards owned
    set card_exp = least(
          (p_config->'enhancement'->'expRequirements'->>(owned.enhancement))::integer,
          owned.card_exp + p_card_exp
        ),
        updated_at = now()
    where owned.user_id = p_user_id and owned.card_id = v_card->>'cardId';
  end loop;
end;
$$;

create or replace function public.gacha_s2_grant_ex_milestones(
  p_user_id uuid,
  p_highest_stage integer,
  p_claims jsonb,
  p_config jsonb
) returns jsonb
language plpgsql
as $$
declare
  v_claims jsonb := coalesce(p_claims, '{}'::jsonb);
  v_awards jsonb := '[]'::jsonb;
  v_milestone jsonb;
  v_key text;
  v_card_id text;
begin
  if coalesce((p_config->'exDistributionRules'->>'enabled')::boolean, false) is not true then
    return jsonb_build_object('claims', v_claims, 'awards', v_awards);
  end if;
  for v_milestone in
    select value from jsonb_array_elements(p_config->'exDistributionRules'->'milestones')
    order by (value->>'clearedStage')::integer
  loop
    v_key := v_milestone->>'clearedStage';
    v_card_id := v_milestone->>'cardId';
    if p_highest_stage < v_key::integer or v_claims ? v_key then continue; end if;
    insert into public.gacha_s2_player_cards (user_id, card_id, copies)
    values (p_user_id, v_card_id, 1)
    on conflict (user_id, card_id) do update
      set copies = public.gacha_s2_player_cards.copies + 1, updated_at = now();
    insert into public.gacha_s2_collection_records (user_id, card_id)
    values (p_user_id, v_card_id)
    on conflict (user_id, card_id) do nothing;
    v_claims := jsonb_set(v_claims, array[v_key], to_jsonb(v_card_id), true);
    v_awards := v_awards || jsonb_build_array(jsonb_build_object(
      'clearedStage', v_key::integer, 'cardId', v_card_id
    ));
  end loop;
  return jsonb_build_object('claims', v_claims, 'awards', v_awards);
end;
$$;

create or replace function public.gacha_s2_minigame_state(p_user_id uuid, p_play_date date)
returns jsonb
language sql
stable
strict
as $$
  select jsonb_build_object(
    'date', to_char(p_play_date, 'YYYY-MM-DD'),
    'pointsEarned', coalesce(sum(points_earned), 0),
    'pointsEarnedByGame', jsonb_build_object(
      'memory', coalesce(max(points_earned) filter (where game = 'memory'), 0),
      'sumTen', coalesce(max(points_earned) filter (where game = 'sumTen'), 0)
    ),
    'plays', coalesce(sum(plays), 0),
    'bestMemory', coalesce(max(best_score) filter (where game = 'memory'), 0),
    'bestSumTen', coalesce(max(best_score) filter (where game = 'sumTen'), 0)
  )
  from public.gacha_s2_minigame_daily
  where user_id = p_user_id and play_date = p_play_date;
$$;

create or replace function public.gacha_s2_memory_board(
  p_seed bigint,
  p_pairs integer
) returns jsonb
language sql
stable
strict
as $$
  with selected as (
    select card_id
    from public.gacha_s2_card_catalog
    where rarity <> 'EX' and not is_group
    order by encode(digest(p_seed::text || ':card:' || card_id, 'sha256'), 'hex')
    limit p_pairs
  ), doubled as (
    select card_id, copy
    from selected cross join generate_series(0, 1) as copies(copy)
  )
  select jsonb_agg(card_id order by encode(
    digest(p_seed::text || ':deck:' || card_id || ':' || copy::text, 'sha256'), 'hex'
  ))
  from doubled;
$$;

create or replace function public.gacha_s2_sum_ten_board(p_seed bigint)
returns jsonb
language sql
immutable
strict
as $$
  select jsonb_agg(1 + floor(public.gacha_s2_seed_roll(p_seed, tile_index) * 9)::integer order by tile_index)
  from generate_series(0, 169) as tiles(tile_index);
$$;

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
  v_matched boolean[];
  v_open integer[] := '{}'::integer[];
  v_action jsonb;
  v_index integer;
  v_at_ms bigint;
  v_previous_at bigint := 0;
  v_next_allowed_at bigint := 0;
  v_max_at bigint := least(p_time_limit_seconds::bigint * 1000, p_server_elapsed_ms + 1000);
  v_left integer;
  v_right integer;
  v_streak integer := 0;
  v_score integer := 0;
  v_matches integer := 0;
begin
  if v_count not in (16, 36) or jsonb_array_length(p_input_log) > 400 then
    return jsonb_build_object('valid', false, 'reason', 'INVALID_LOG_SIZE');
  end if;
  v_matched := array_fill(false, array[v_count]);
  for v_action in select value from jsonb_array_elements(p_input_log) loop
    if jsonb_typeof(v_action) <> 'object'
      or coalesce(v_action->>'index', '') !~ '^\d+$'
      or coalesce(v_action->>'atMs', '') !~ '^\d+$' then
      return jsonb_build_object('valid', false, 'reason', 'INVALID_ACTION');
    end if;
    v_index := (v_action->>'index')::integer;
    v_at_ms := (v_action->>'atMs')::bigint;
    if v_index < 0 or v_index >= v_count or v_at_ms < v_previous_at
      or v_at_ms < v_next_allowed_at or v_at_ms > v_max_at
      or v_matched[v_index + 1] or v_index = any(v_open) then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION');
    end if;
    v_previous_at := v_at_ms;
    v_open := array_append(v_open, v_index);
    if cardinality(v_open) < 2 then continue; end if;
    v_left := v_open[1];
    v_right := v_open[2];
    if p_board->>(v_left) = p_board->>(v_right) then
      v_matched[v_left + 1] := true;
      v_matched[v_right + 1] := true;
      v_matches := v_matches + 1;
      v_streak := v_streak + 1;
      v_score := v_score + 100 + v_streak * 20;
      v_next_allowed_at := v_at_ms + 320;
    else
      v_streak := 0;
      v_score := greatest(0, v_score - 10);
      v_next_allowed_at := v_at_ms + 650;
    end if;
    v_open := '{}'::integer[];
  end loop;
  return jsonb_build_object(
    'valid', true,
    'score', v_score,
    'completed', v_matches = v_count / 2,
    'matches', v_matches
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
  v_action jsonb;
  v_start integer;
  v_end integer;
  v_at_ms bigint;
  v_previous_at bigint := 0;
  v_max_at bigint := least(p_time_limit_seconds::bigint * 1000, p_server_elapsed_ms + 1000);
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
  v_selected integer;
  v_score integer := 0;
  v_remaining integer := 170;
begin
  if v_count <> 170 or jsonb_array_length(p_input_log) > 500 then
    return jsonb_build_object('valid', false, 'reason', 'INVALID_LOG_SIZE');
  end if;
  v_active := array_fill(true, array[v_count]);
  for v_action in select value from jsonb_array_elements(p_input_log) loop
    if jsonb_typeof(v_action) <> 'object'
      or coalesce(v_action->>'start', '') !~ '^\d+$'
      or coalesce(v_action->>'end', '') !~ '^\d+$'
      or coalesce(v_action->>'atMs', '') !~ '^\d+$' then
      return jsonb_build_object('valid', false, 'reason', 'INVALID_ACTION');
    end if;
    v_start := (v_action->>'start')::integer;
    v_end := (v_action->>'end')::integer;
    v_at_ms := (v_action->>'atMs')::bigint;
    if v_start < 0 or v_start >= v_count or v_end < 0 or v_end >= v_count
      or v_at_ms < v_previous_at or v_at_ms > v_max_at then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION');
    end if;
    v_previous_at := v_at_ms;
    v_start_row := v_start / 17;
    v_end_row := v_end / 17;
    v_start_column := v_start % 17;
    v_end_column := v_end % 17;
    v_min_row := least(v_start_row, v_end_row);
    v_max_row := greatest(v_start_row, v_end_row);
    v_min_column := least(v_start_column, v_end_column);
    v_max_column := greatest(v_start_column, v_end_column);
    v_sum := 0;
    v_selected := 0;
    for v_index in 0..169 loop
      v_row := v_index / 17;
      v_column := v_index % 17;
      if v_active[v_index + 1]
        and v_row between v_min_row and v_max_row
        and v_column between v_min_column and v_max_column then
        v_sum := v_sum + (p_board->>(v_index))::integer;
        v_selected := v_selected + 1;
      end if;
    end loop;
    if v_selected > 0 and v_sum = 10 then
      for v_index in 0..169 loop
        v_row := v_index / 17;
        v_column := v_index % 17;
        if v_active[v_index + 1]
          and v_row between v_min_row and v_max_row
          and v_column between v_min_column and v_max_column then
          v_active[v_index + 1] := false;
          v_remaining := v_remaining - 1;
        end if;
      end loop;
      v_score := v_score + v_selected;
    end if;
  end loop;
  return jsonb_build_object(
    'valid', true,
    'score', v_score,
    'completed', v_remaining = 0,
    'remainingTiles', v_remaining
  );
end;
$$;

create or replace function public.gacha_s2_start_adventure_run(
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
  v_adventure_runs jsonb;
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
  v_run_id uuid := gen_random_uuid();
  v_seed bigint;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_verified_cleared_stages is null or p_verified_cleared_stages not between 0 and 50
    or p_verification_digest is null or p_verification_digest !~ '^[0-9a-fA-F]{64}$' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '모험 시작 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'startAdventureRun', 'expectedRevision', p_expected_revision,
    'verifiedClearedStages', p_verified_cleared_stages,
    'verificationDigest', lower(p_verification_digest)
  )::text, 'sha256'), 'hex');

  select revision, adventure_runs into v_revision, v_adventure_runs
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
  v_seed := public.gacha_s2_new_seed();

  insert into public.gacha_s2_adventure_runs (
    run_id, user_id, start_command_id, mode, status, balance_version, server_seed,
    formation_snapshot, verified_cleared_stages, verification_digest
  ) values (
    v_run_id, p_user_id, p_idempotency_key, 'normal', 'active', v_balance_version, v_seed,
    v_formation, p_verified_cleared_stages, lower(p_verification_digest)
  );
  update public.gacha_s2_player_states
  set adventure_runs = jsonb_build_object('windowStartedAt', v_window_started, 'count', v_run_count + 1),
      adventure_run = jsonb_build_object(
        'active', true, 'currentStage', 1, 'clearedStages', 0,
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
      'runId', v_run_id, 'mode', 'normal',
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
    v_run.verified_cleared_stages * (v_config->'adventureRules'->'runReward'->>'pointsBasePerStage')::integer
      + (v_config->'adventureRules'->'runReward'->>'pointsGrowthPerStage')::integer
        * v_run.verified_cleared_stages * (v_run.verified_cleared_stages + 1) / 2
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
  v_today text := to_char(timezone('Asia/Seoul', now()), 'YYYY-MM-DD');
  v_interval_ms bigint;
  v_recovered integer;
  v_quick_count integer;
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
    or p_verified_cleared_stages is null or p_verified_cleared_stages not between 1 and 50
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
  v_quick_count := case when v_quick->>'date' = v_today then coalesce((v_quick->>'count')::integer, 0) else 0 end;
  if v_quick_count >= (v_config->'rewardRules'->>'quickBattleDailyLimit')::integer then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '오늘 빠른 전투 횟수를 모두 사용했습니다.', v_revision, null, null);
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
      quick_battle = jsonb_build_object('date', v_today, 'count', v_quick_count + 1),
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

revoke all on table public.gacha_s2_adventure_runs from public, anon, authenticated;
revoke all on table public.gacha_s2_minigame_daily from public, anon, authenticated;
revoke all on table public.gacha_s2_minigame_runs from public, anon, authenticated;
revoke all on function public.gacha_s2_formation_snapshot(uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_roll_adventure_drop(jsonb, integer, bigint, integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_grant_formation_exp(uuid, jsonb, integer, jsonb) from public, anon, authenticated;
revoke all on function public.gacha_s2_grant_ex_milestones(uuid, integer, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.gacha_s2_minigame_state(uuid, date) from public, anon, authenticated;
revoke all on function public.gacha_s2_memory_board(bigint, integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_sum_ten_board(bigint) from public, anon, authenticated;
revoke all on function public.gacha_s2_verify_memory_log(jsonb, jsonb, integer, bigint) from public, anon, authenticated;
revoke all on function public.gacha_s2_verify_sum_ten_log(jsonb, jsonb, integer, bigint) from public, anon, authenticated;
revoke all on function public.gacha_s2_start_adventure_run(uuid, bigint, text, integer, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_finish_adventure_run(uuid, bigint, text, uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_claim_quick_battle(uuid, bigint, text, integer, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_start_minigame(uuid, bigint, text, text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_finish_minigame(uuid, bigint, text, uuid, jsonb, integer) from public, anon, authenticated;

grant execute on function public.gacha_s2_start_adventure_run(uuid, bigint, text, integer, text) to service_role;
grant execute on function public.gacha_s2_finish_adventure_run(uuid, bigint, text, uuid) to service_role;
grant execute on function public.gacha_s2_claim_quick_battle(uuid, bigint, text, integer, text) to service_role;
grant execute on function public.gacha_s2_start_minigame(uuid, bigint, text, text, text) to service_role;
grant execute on function public.gacha_s2_finish_minigame(uuid, bigint, text, uuid, jsonb, integer) to service_role;

commit;
