-- Card Gacha Season 2: server-authoritative world-boss sessions, attacks, and rewards.
-- REVIEW ONLY. Run after migrations 001-005. Do not execute against production without approval.

begin;

do $$
begin
  if to_regclass('public.gacha_s2_adventure_runs') is null
    or to_regprocedure('public.gacha_s2_formation_snapshot(uuid)') is null
    or to_regprocedure('public.gacha_s2_grant_formation_exp(uuid,jsonb,integer,jsonb)') is null then
    raise exception 'missing Season 2 gameplay schema: run migrations 001-005 first';
  end if;
end;
$$;

alter table public.gacha_s2_player_states
  alter column world_boss set default '{
    "eventId":"standby","startedAt":0,"endsAt":1,"attempts":0,
    "bestDamage":0,"totalDamage":0,"claimedTier":-1,"lastDamage":0
  }'::jsonb;

update public.gacha_s2_player_states
set world_boss = '{
  "eventId":"standby","startedAt":0,"endsAt":1,"attempts":0,
  "bestDamage":0,"totalDamage":0,"claimedTier":-1,"lastDamage":0
}'::jsonb
where world_boss = '{}'::jsonb;

create table if not exists public.gacha_s2_world_boss_events (
  event_id text primary key check (event_id ~ '^noise-zero-[0-9]{8}-[0-9]{2}$'),
  balance_version text not null references public.gacha_s2_balance_versions(version),
  starts_at timestamptz not null,
  raid_ends_at timestamptz not null,
  ends_at timestamptz not null,
  max_hp bigint not null check (max_hp > 0),
  current_hp bigint not null check (current_hp >= 0 and current_hp <= max_hp),
  player_damage bigint not null default 0 check (player_damage >= 0),
  server_damage_per_second bigint not null check (server_damage_per_second >= 0),
  defeated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (raid_ends_at > starts_at and ends_at > raid_ends_at),
  check (defeated_at is null or defeated_at >= starts_at)
);

create table if not exists public.gacha_s2_world_boss_players (
  event_id text not null references public.gacha_s2_world_boss_events(event_id) on delete cascade,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  attempts integer not null default 0 check (attempts between 0 and 3),
  best_damage bigint not null default 0 check (best_damage >= 0),
  total_damage bigint not null default 0 check (total_damage >= 0),
  last_damage bigint not null default 0 check (last_damage >= 0),
  claimed_tier integer not null default -1 check (claimed_tier between -1 and 5),
  reward_points integer not null default 0 check (reward_points between 0 and 10000),
  bonus_item_id text,
  last_attempt_at timestamptz,
  claimed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id),
  check ((claimed_at is null and claimed_tier = -1 and reward_points = 0)
    or (claimed_at is not null and claimed_tier >= 0))
);

create table if not exists public.gacha_s2_world_boss_attempts (
  attempt_id uuid primary key default gen_random_uuid(),
  event_id text not null references public.gacha_s2_world_boss_events(event_id) on delete cascade,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  command_id text not null,
  attempt_number integer not null check (attempt_number between 1 and 3),
  balance_version text not null references public.gacha_s2_balance_versions(version),
  server_seed bigint not null check (server_seed between 0 and 4294967295),
  formation_snapshot jsonb not null check (
    jsonb_typeof(formation_snapshot) = 'array' and jsonb_array_length(formation_snapshot) = 5
  ),
  verified_damage bigint not null check (verified_damage > 0),
  verification_digest text not null check (verification_digest ~ '^[0-9a-fA-F]{64}$'),
  card_exp integer not null check (card_exp >= 0),
  created_at timestamptz not null default now(),
  unique (event_id, user_id, attempt_number),
  unique (user_id, command_id)
);

create index if not exists idx_gacha_s2_world_boss_events_window
  on public.gacha_s2_world_boss_events(starts_at desc, ends_at desc);
create index if not exists idx_gacha_s2_world_boss_players_rank
  on public.gacha_s2_world_boss_players(event_id, total_damage desc, updated_at);
create index if not exists idx_gacha_s2_world_boss_attempts_user_created
  on public.gacha_s2_world_boss_attempts(user_id, created_at desc);

alter table public.gacha_s2_world_boss_events enable row level security;
alter table public.gacha_s2_world_boss_players enable row level security;
alter table public.gacha_s2_world_boss_attempts enable row level security;

drop policy if exists gacha_s2_world_boss_events_read on public.gacha_s2_world_boss_events;
create policy gacha_s2_world_boss_events_read
  on public.gacha_s2_world_boss_events
  for select
  to authenticated
  using (ends_at >= now() - interval '1 hour' and starts_at <= now() + interval '1 day');

create or replace function public.gacha_s2_world_boss_schedule(
  p_config jsonb,
  p_now timestamptz default now()
) returns jsonb
language plpgsql
stable
strict
as $$
declare
  v_local_now timestamp := timezone('Asia/Seoul', p_now);
  v_today date := timezone('Asia/Seoul', p_now)::date;
  v_day_offset integer;
  v_hour integer;
  v_slot_local timestamp;
  v_starts_at timestamptz;
  v_raid_ends_at timestamptz;
  v_ends_at timestamptz;
  v_event_id text;
  v_current jsonb := null;
  v_next jsonb := null;
  v_raid_seconds integer := (p_config->'worldBossRules'->>'raidDurationSeconds')::integer;
  v_event_seconds integer := (p_config->'worldBossRules'->>'eventDurationSeconds')::integer;
begin
  if v_raid_seconds <= 0 or v_event_seconds <= v_raid_seconds then
    raise exception 'invalid world boss durations';
  end if;
  for v_day_offset in 0..1 loop
    for v_hour in
      select value::integer
      from jsonb_array_elements_text(p_config->'worldBossRules'->'scheduleHours')
      order by value::integer
    loop
      v_slot_local := (v_today + v_day_offset)::timestamp + make_interval(hours => v_hour);
      v_starts_at := v_slot_local at time zone 'Asia/Seoul';
      v_raid_ends_at := v_starts_at + make_interval(secs => v_raid_seconds);
      v_ends_at := v_starts_at + make_interval(secs => v_event_seconds);
      v_event_id := 'noise-zero-' || to_char(v_slot_local, 'YYYYMMDD-HH24');
      if v_current is null and p_now >= v_starts_at and p_now < v_ends_at then
        v_current := jsonb_build_object(
          'eventId', v_event_id,
          'startsAt', floor(extract(epoch from v_starts_at) * 1000)::bigint,
          'raidEndsAt', floor(extract(epoch from v_raid_ends_at) * 1000)::bigint,
          'endsAt', floor(extract(epoch from v_ends_at) * 1000)::bigint
        );
      end if;
      if v_next is null and v_starts_at > p_now then
        v_next := jsonb_build_object(
          'eventId', v_event_id,
          'startsAt', floor(extract(epoch from v_starts_at) * 1000)::bigint,
          'raidEndsAt', floor(extract(epoch from v_raid_ends_at) * 1000)::bigint,
          'endsAt', floor(extract(epoch from v_ends_at) * 1000)::bigint
        );
      end if;
    end loop;
  end loop;
  return jsonb_build_object(
    'live', v_current is not null,
    'currentSlot', v_current,
    'nextSlot', v_next,
    'serverTime', floor(extract(epoch from p_now) * 1000)::bigint,
    'kstDate', to_char(v_local_now, 'YYYY-MM-DD')
  );
end;
$$;

create or replace function public.gacha_s2_ensure_world_boss_schedule(
  p_now timestamptz default now()
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_version text;
  v_config jsonb;
  v_schedule jsonb;
  v_slot jsonb;
begin
  select version, config into v_version, v_config
  from public.gacha_s2_balance_versions
  where active;
  if v_config is null then
    raise exception 'active balance version not found';
  end if;
  v_schedule := public.gacha_s2_world_boss_schedule(v_config, p_now);
  for v_slot in
    select value
    from jsonb_array_elements(jsonb_build_array(v_schedule->'currentSlot', v_schedule->'nextSlot'))
  loop
    if jsonb_typeof(v_slot) <> 'object' then continue; end if;
    insert into public.gacha_s2_world_boss_events (
      event_id, balance_version, starts_at, raid_ends_at, ends_at,
      max_hp, current_hp, server_damage_per_second
    ) values (
      v_slot->>'eventId',
      v_version,
      to_timestamp((v_slot->>'startsAt')::numeric / 1000.0),
      to_timestamp((v_slot->>'raidEndsAt')::numeric / 1000.0),
      to_timestamp((v_slot->>'endsAt')::numeric / 1000.0),
      (v_config->'worldBossRules'->>'maxHp')::bigint,
      (v_config->'worldBossRules'->>'maxHp')::bigint,
      (v_config->'worldBossRules'->>'serverDamagePerSecond')::bigint
    ) on conflict (event_id) do nothing;
  end loop;
  return v_schedule;
end;
$$;

create or replace function public.gacha_s2_sync_world_boss_event(
  p_event_id text,
  p_now timestamptz default now()
) returns public.gacha_s2_world_boss_events
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_event public.gacha_s2_world_boss_events%rowtype;
  v_elapsed_seconds bigint;
  v_server_damage bigint;
  v_next_hp bigint;
begin
  select * into v_event
  from public.gacha_s2_world_boss_events
  where event_id = p_event_id
  for update;
  if not found then return null; end if;
  v_elapsed_seconds := floor(greatest(
    0,
    least(
      extract(epoch from (v_event.raid_ends_at - v_event.starts_at)),
      extract(epoch from (p_now - v_event.starts_at))
    )
  ))::bigint;
  v_server_damage := least(v_event.max_hp, v_elapsed_seconds * v_event.server_damage_per_second);
  v_next_hp := greatest(0, v_event.max_hp - v_event.player_damage - v_server_damage);
  update public.gacha_s2_world_boss_events
  set current_hp = v_next_hp,
      defeated_at = case
        when v_next_hp = 0 then coalesce(defeated_at, least(p_now, raid_ends_at))
        else defeated_at
      end,
      updated_at = now()
  where event_id = p_event_id
  returning * into v_event;
  return v_event;
end;
$$;

create or replace function public.gacha_s2_world_boss_progress(
  p_user_id uuid,
  p_event_id text
) returns jsonb
language sql
stable
strict
as $$
  select jsonb_build_object(
    'eventId', event.event_id,
    'startedAt', floor(extract(epoch from event.starts_at) * 1000)::bigint,
    'endsAt', floor(extract(epoch from event.ends_at) * 1000)::bigint,
    'attempts', coalesce(player.attempts, 0),
    'bestDamage', coalesce(player.best_damage, 0),
    'totalDamage', coalesce(player.total_damage, 0),
    'claimedTier', coalesce(player.claimed_tier, -1),
    'lastDamage', coalesce(player.last_damage, 0)
  )
  from public.gacha_s2_world_boss_events event
  left join public.gacha_s2_world_boss_players player
    on player.event_id = event.event_id and player.user_id = p_user_id
  where event.event_id = p_event_id;
$$;

create or replace function public.gacha_s2_tick_world_boss_events(
  p_now timestamptz default now()
) returns integer
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id text;
  v_count integer := 0;
begin
  perform public.gacha_s2_ensure_world_boss_schedule(p_now);
  for v_event_id in
    select event_id
    from public.gacha_s2_world_boss_events
    where starts_at <= p_now and raid_ends_at >= p_now
    order by starts_at
  loop
    perform public.gacha_s2_sync_world_boss_event(v_event_id, p_now);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.gacha_s2_roll_world_boss_drop(
  p_config jsonb,
  p_defeated boolean,
  p_seed bigint,
  p_counter integer default 0
) returns text
language plpgsql
immutable
strict
as $$
declare
  v_rule jsonb;
  v_weights jsonb;
  v_roll numeric;
  v_item_id text;
begin
  v_rule := p_config->'bonusDropRules'->'worldBoss'->(
    case when p_defeated then 'cleared' else 'failed' end
  );
  if v_rule is null
    or public.gacha_s2_seed_roll(p_seed, p_counter) >= (v_rule->>'dropRate')::numeric then
    return null;
  end if;
  v_weights := case
    when public.gacha_s2_seed_roll(p_seed, p_counter + 1) < (v_rule->>'packShare')::numeric
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

create or replace function public.gacha_s2_get_world_boss_status(
  p_user_id uuid,
  p_event_id text default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
  v_schedule jsonb;
  v_event_id text;
  v_event public.gacha_s2_world_boss_events%rowtype;
  v_config jsonb;
  v_progress jsonb;
  v_participants integer := 0;
  v_rank integer := null;
  v_leaderboard jsonb := '[]'::jsonb;
  v_raid_seconds integer;
  v_battle_seconds integer;
  v_hp_ratio numeric;
begin
  if p_user_id is null then return null; end if;
  v_schedule := public.gacha_s2_ensure_world_boss_schedule(v_now);
  v_event_id := coalesce(p_event_id, v_schedule->'currentSlot'->>'eventId');
  if v_event_id is null then
    return jsonb_build_object(
      'serverTime', public.gacha_s2_now_ms(),
      'schedule', v_schedule,
      'event', null,
      'player', null,
      'leaderboard', '[]'::jsonb
    );
  end if;
  v_event := public.gacha_s2_sync_world_boss_event(v_event_id, v_now);
  if v_event.event_id is null then return null; end if;
  select config into v_config
  from public.gacha_s2_balance_versions
  where version = v_event.balance_version;
  v_progress := public.gacha_s2_world_boss_progress(p_user_id, v_event_id);
  select count(*)::integer into v_participants
  from public.gacha_s2_world_boss_players
  where event_id = v_event_id and attempts > 0;
  if coalesce((v_progress->>'attempts')::integer, 0) > 0 then
    select 1 + count(*)::integer into v_rank
    from public.gacha_s2_world_boss_players
    where event_id = v_event_id
      and total_damage > (v_progress->>'totalDamage')::bigint;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank', ranked.rank,
    'nickname', ranked.nickname,
    'damage', ranked.total_damage
  ) order by ranked.rank), '[]'::jsonb) into v_leaderboard
  from (
    select (row_number() over (order by player.total_damage desc, player.updated_at, player.user_id))::integer as rank,
      account.nickname,
      player.total_damage
    from public.gacha_s2_world_boss_players player
    join public.gacha_s2_accounts account on account.id = player.user_id
    where player.event_id = v_event_id and player.attempts > 0
    order by player.total_damage desc, player.updated_at, player.user_id
    limit 10
  ) ranked;
  v_raid_seconds := (v_config->'worldBossRules'->>'raidDurationSeconds')::integer;
  v_battle_seconds := (v_config->'worldBossRules'->>'battleDuration')::integer;
  v_hp_ratio := v_event.current_hp::numeric / v_event.max_hp;
  return jsonb_build_object(
    'serverTime', public.gacha_s2_now_ms(),
    'schedule', v_schedule,
    'event', jsonb_build_object(
      'eventId', v_event.event_id,
      'startsAt', floor(extract(epoch from v_event.starts_at) * 1000)::bigint,
      'raidEndsAt', floor(extract(epoch from v_event.raid_ends_at) * 1000)::bigint,
      'endsAt', floor(extract(epoch from v_event.ends_at) * 1000)::bigint,
      'currentHp', v_event.current_hp,
      'maxHp', v_event.max_hp,
      'defeated', v_event.current_hp = 0,
      'resultsOpen', v_now >= v_event.raid_ends_at and v_now < v_event.ends_at,
      'active', v_now >= v_event.starts_at and v_now < v_event.raid_ends_at and v_event.current_hp > 0,
      'phase', case when v_hp_ratio > 0.66 then 1 when v_hp_ratio > 0.33 then 2 else 3 end,
      'participants', v_participants
    ),
    'player', v_progress || jsonb_build_object(
      'rank', v_rank,
      'canAttack', v_now >= v_event.starts_at
        and v_now + make_interval(secs => v_battle_seconds) < v_event.raid_ends_at
        and v_event.current_hp > 0
        and (v_progress->>'attempts')::integer < (v_config->'worldBossRules'->>'maxAttempts')::integer
    ),
    'leaderboard', v_leaderboard,
    'raidDurationSeconds', v_raid_seconds
  );
end;
$$;

create or replace function public.gacha_s2_attack_world_boss(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_event_id text,
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
  v_schedule jsonb;
  v_event public.gacha_s2_world_boss_events%rowtype;
  v_config jsonb;
  v_formation jsonb;
  v_attempts integer := 0;
  v_attempt_number integer;
  v_card_exp integer;
  v_seed bigint;
  v_progress jsonb;
  v_snapshot jsonb;
  v_response jsonb;
  v_now timestamptz := now();
  v_now_ms bigint := public.gacha_s2_now_ms();
  v_battle_seconds integer;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_event_id is null or p_event_id !~ '^noise-zero-[0-9]{8}-[0-9]{2}$'
    or p_verified_damage is null or p_verified_damage <= 0
    or p_verification_digest is null or p_verification_digest !~ '^[0-9a-fA-F]{64}$' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '월드보스 공격 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'attackWorldBoss', 'expectedRevision', p_expected_revision,
    'eventId', p_event_id, 'verifiedDamage', p_verified_damage,
    'verificationDigest', lower(p_verification_digest)
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
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'attackWorldBoss' then
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
  v_schedule := public.gacha_s2_ensure_world_boss_schedule(v_now);
  if (v_schedule->'currentSlot'->>'eventId') is distinct from p_event_id then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '현재 진행 중인 월드보스 회차가 아닙니다.', v_revision, null, null);
  end if;
  v_event := public.gacha_s2_sync_world_boss_event(p_event_id, v_now);
  if v_event.event_id is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '월드보스 회차를 찾을 수 없습니다.', v_revision, null, null);
  end if;
  select config into v_config
  from public.gacha_s2_balance_versions
  where version = v_event.balance_version;
  v_battle_seconds := (v_config->'worldBossRules'->>'battleDuration')::integer;
  if v_now < v_event.starts_at
    or v_now + make_interval(secs => v_battle_seconds) >= v_event.raid_ends_at
    or v_event.current_hp = 0 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '현재 월드보스 공격을 시작할 수 없습니다.', v_revision, null, null);
  end if;
  if p_verified_damage > v_event.max_hp then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '검증 피해량이 허용 범위를 초과했습니다.', v_revision, null, null);
  end if;
  v_formation := public.gacha_s2_formation_snapshot(p_user_id);
  if v_formation is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '전투 카드 5장 편성이 필요합니다.', v_revision, null, null);
  end if;
  select attempts into v_attempts
  from public.gacha_s2_world_boss_players
  where event_id = p_event_id and user_id = p_user_id
  for update;
  v_attempts := coalesce(v_attempts, 0);
  if v_attempts >= (v_config->'worldBossRules'->>'maxAttempts')::integer then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '이번 회차 도전 횟수를 모두 사용했습니다.', v_revision, null, null);
  end if;
  v_attempt_number := v_attempts + 1;
  v_card_exp := (v_config->'worldBossRules'->>'cardExpPerAttempt')::integer;
  v_seed := public.gacha_s2_new_seed();

  update public.gacha_s2_world_boss_events
  set player_damage = player_damage + p_verified_damage,
      current_hp = greatest(0, current_hp - p_verified_damage),
      defeated_at = case
        when current_hp - p_verified_damage <= 0 then coalesce(defeated_at, v_now)
        else defeated_at
      end,
      updated_at = now()
  where event_id = p_event_id
  returning * into v_event;
  insert into public.gacha_s2_world_boss_attempts (
    event_id, user_id, command_id, attempt_number, balance_version, server_seed,
    formation_snapshot, verified_damage, verification_digest, card_exp
  ) values (
    p_event_id, p_user_id, p_idempotency_key, v_attempt_number, v_event.balance_version, v_seed,
    v_formation, p_verified_damage, lower(p_verification_digest), v_card_exp
  );
  insert into public.gacha_s2_world_boss_players (
    event_id, user_id, attempts, best_damage, total_damage, last_damage, last_attempt_at
  ) values (
    p_event_id, p_user_id, 1, p_verified_damage, p_verified_damage, p_verified_damage, v_now
  ) on conflict (event_id, user_id) do update
  set attempts = public.gacha_s2_world_boss_players.attempts + 1,
      best_damage = greatest(public.gacha_s2_world_boss_players.best_damage, excluded.last_damage),
      total_damage = public.gacha_s2_world_boss_players.total_damage + excluded.last_damage,
      last_damage = excluded.last_damage,
      last_attempt_at = excluded.last_attempt_at,
      updated_at = now();
  perform public.gacha_s2_grant_formation_exp(p_user_id, v_formation, v_card_exp, v_config);
  v_progress := public.gacha_s2_world_boss_progress(p_user_id, p_event_id);
  update public.gacha_s2_player_states
  set world_boss = v_progress,
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
      'eventId', p_event_id,
      'attemptNumber', v_attempt_number,
      'damage', p_verified_damage,
      'cardExp', v_card_exp,
      'currentHp', v_event.current_hp,
      'maxHp', v_event.max_hp,
      'defeated', v_event.current_hp = 0,
      'verificationDigest', lower(p_verification_digest)
    )
  );
  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'attackWorldBoss', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'attackWorldBoss', v_request_hash, p_expected_revision, v_revision, v_seed
  );
  return v_response;
end;
$$;

create or replace function public.gacha_s2_claim_world_boss_reward(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_event_id text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_support_items jsonb;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_schedule jsonb;
  v_event public.gacha_s2_world_boss_events%rowtype;
  v_player public.gacha_s2_world_boss_players%rowtype;
  v_config jsonb;
  v_tier jsonb;
  v_tier_index integer;
  v_defeated boolean;
  v_points integer;
  v_seed bigint;
  v_bonus_item text;
  v_progress jsonb;
  v_snapshot jsonb;
  v_response jsonb;
  v_now timestamptz := now();
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_event_id is null or p_event_id !~ '^noise-zero-[0-9]{8}-[0-9]{2}$' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '월드보스 보상 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;
  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'claimWorldBossReward', 'expectedRevision', p_expected_revision, 'eventId', p_event_id
  )::text, 'sha256'), 'hex');
  select revision, support_items into v_revision, v_support_items
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
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'claimWorldBossReward' then
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
  v_schedule := public.gacha_s2_ensure_world_boss_schedule(v_now);
  if (v_schedule->'currentSlot'->>'eventId') is distinct from p_event_id then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '현재 결과 공개 중인 회차가 아닙니다.', v_revision, null, null);
  end if;
  v_event := public.gacha_s2_sync_world_boss_event(p_event_id, v_now);
  if v_event.event_id is null or v_now < v_event.raid_ends_at or v_now >= v_event.ends_at then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '결과 공개 시간에만 보상을 받을 수 있습니다.', v_revision, null, null);
  end if;
  select * into v_player
  from public.gacha_s2_world_boss_players
  where event_id = p_event_id and user_id = p_user_id
  for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '이번 회차 참가 기록이 없습니다.', v_revision, null, null);
  end if;
  if v_player.attempts = 0 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '이번 회차 참가 기록이 없습니다.', v_revision, null, null);
  end if;
  if v_player.claimed_at is not null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '이미 이번 회차 보상을 받았습니다.', v_revision, null, null);
  end if;
  select config into v_config
  from public.gacha_s2_balance_versions
  where version = v_event.balance_version;
  select (ordinality - 1)::integer, tier into v_tier_index, v_tier
  from jsonb_array_elements(v_config->'worldBossRules'->'rewardTiers') with ordinality as tiers(tier, ordinality)
  where (tier->>'damage')::bigint <= v_player.total_damage
  order by ordinality desc
  limit 1;
  if v_tier is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '달성한 월드보스 보상 단계가 없습니다.', v_revision, null, null);
  end if;
  v_defeated := v_event.current_hp = 0;
  v_points := case
    when v_defeated then (v_tier->>'points')::integer
    else (v_tier->>'failurePoints')::integer
  end;
  v_seed := public.gacha_s2_new_seed();
  v_bonus_item := public.gacha_s2_roll_world_boss_drop(v_config, v_defeated, v_seed, 20);
  if v_bonus_item is not null then
    v_support_items := jsonb_set(
      v_support_items, array[v_bonus_item],
      to_jsonb(coalesce((v_support_items->>v_bonus_item)::integer, 0) + 1), true
    );
  end if;
  update public.gacha_s2_world_boss_players
  set claimed_tier = v_tier_index,
      reward_points = v_points,
      bonus_item_id = v_bonus_item,
      claimed_at = v_now,
      updated_at = now()
  where event_id = p_event_id and user_id = p_user_id;
  v_progress := public.gacha_s2_world_boss_progress(p_user_id, p_event_id);
  update public.gacha_s2_player_states
  set points = points + v_points,
      support_items = v_support_items,
      world_boss = v_progress,
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
      'eventId', p_event_id,
      'tier', v_tier_index,
      'defeated', v_defeated,
      'points', v_points,
      'bonusItemId', v_bonus_item
    )
  );
  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'claimWorldBossReward', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed
  ) values (
    p_user_id, p_idempotency_key, 'claimWorldBossReward', v_request_hash, p_expected_revision, v_revision, v_seed
  );
  return v_response;
end;
$$;

revoke all on table public.gacha_s2_world_boss_events from public, anon, authenticated;
revoke all on table public.gacha_s2_world_boss_players from public, anon, authenticated;
revoke all on table public.gacha_s2_world_boss_attempts from public, anon, authenticated;
grant select on table public.gacha_s2_world_boss_events to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'gacha_s2_world_boss_events'
    ) then
    alter publication supabase_realtime add table public.gacha_s2_world_boss_events;
  end if;
end;
$$;

revoke all on function public.gacha_s2_world_boss_schedule(jsonb, timestamptz) from public, anon, authenticated;
revoke all on function public.gacha_s2_ensure_world_boss_schedule(timestamptz) from public, anon, authenticated;
revoke all on function public.gacha_s2_sync_world_boss_event(text, timestamptz) from public, anon, authenticated;
revoke all on function public.gacha_s2_world_boss_progress(uuid, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_tick_world_boss_events(timestamptz) from public, anon, authenticated;
revoke all on function public.gacha_s2_roll_world_boss_drop(jsonb, boolean, bigint, integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_get_world_boss_status(uuid, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_attack_world_boss(uuid, bigint, text, text, bigint, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_claim_world_boss_reward(uuid, bigint, text, text) from public, anon, authenticated;

grant execute on function public.gacha_s2_get_world_boss_status(uuid, text) to service_role;
grant execute on function public.gacha_s2_tick_world_boss_events(timestamptz) to service_role;
grant execute on function public.gacha_s2_attack_world_boss(uuid, bigint, text, text, bigint, text) to service_role;
grant execute on function public.gacha_s2_claim_world_boss_reward(uuid, bigint, text, text) to service_role;

commit;
