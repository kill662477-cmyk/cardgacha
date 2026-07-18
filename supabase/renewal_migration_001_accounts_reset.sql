-- Card Gacha Season 2: account carryover and clean game-state bootstrap.
-- REVIEW ONLY. Do not run against production until the preview counts are approved.
-- Season 1 tables stay read-only until the Season 2 import and cutover are verified.
-- Remove them later with renewal_migration_999_drop_season1.sql.

create extension if not exists pgcrypto;

do $$
begin
  if to_regclass('public.gacha_users') is null then
    raise exception 'missing season1 source table: public.gacha_users';
  end if;
  if to_regclass('public.gacha_collection') is null then
    raise exception 'missing season1 source table: public.gacha_collection';
  end if;
  if to_regclass('public.gacha_season1_final_top50') is null then
    raise exception 'missing season1 snapshot table: public.gacha_season1_final_top50';
  end if;
  if to_regclass('public.gacha_soop_bridge_keys') is null then
    raise exception 'missing season1 streamer registry: public.gacha_soop_bridge_keys';
  end if;
end;
$$;

create or replace function public.gacha_s2_season1_rank_reward(p_rank integer)
returns integer
language sql
immutable
strict
as $$
  select case
    when p_rank between 1 and 10 then 30000
    when p_rank between 11 and 20 then 20000
    when p_rank between 21 and 30 then 15000
    when p_rank between 31 and 40 then 10000
    when p_rank between 41 and 50 then 5000
    else 0
  end;
$$;

create table if not exists public.gacha_s2_accounts (
  id uuid primary key default gen_random_uuid(),
  legacy_user_id uuid unique,
  nickname text not null check (length(trim(nickname)) between 1 and 40),
  login_key_hash text not null unique check (login_key_hash ~ '^[0-9a-fA-F]{64}$'),
  soop_id text unique,
  legacy_created_at timestamptz,
  season1_final_rank integer unique check (season1_final_rank between 1 and 50),
  season1_rank_reward_points integer not null default 0 check (season1_rank_reward_points in (0, 5000, 10000, 15000, 20000, 30000)),
  is_streamer boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gacha_s2_streamer_bridges (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  soop_id text not null unique,
  key_hash text not null unique check (key_hash ~ '^[0-9a-fA-F]{64}$'),
  active boolean not null default true,
  legacy_created_at timestamptz,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gacha_s2_player_states (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  schema_version integer not null default 2 check (schema_version = 2),
  revision bigint not null default 0 check (revision >= 0),
  points integer not null default 5000 check (points >= 0),
  action_energy integer not null default 120 check (action_energy between 0 and 240),
  max_action_energy integer not null default 120 check (max_action_energy = 120),
  last_energy_at timestamptz not null default now(),
  last_reward_at timestamptz not null default now(),
  cleared_stage integer not null default 0 check (cleared_stage between 0 and 50),
  pending_points integer not null default 0 check (pending_points >= 0),
  representative_card_id text,
  formation text[] not null default '{}'::text[] check (cardinality(formation) <= 5),
  formation_presets jsonb not null default '{}'::jsonb check (jsonb_typeof(formation_presets) = 'object'),
  active_formation_preset_id text,
  support_items jsonb not null default '{
    "energySmall":0,"energyMedium":0,"energyLarge":0,
    "enhance5":0,"enhance10":0,"destructionGuard":0,
    "cardExpPotion":0,"exp30m":0,"exp2h":0,
    "generalTicket":0,"eliteTicket":0,"raceTicket":0,"premiumTicket":0,
    "adventureRunReset":0,"quickBattleReset":0
  }'::jsonb check (jsonb_typeof(support_items) = 'object'),
  active_buffs jsonb not null default '{"cardExpStartAt":0,"cardExpEndAt":0}'::jsonb,
  quick_battle jsonb not null default jsonb_build_object('date', to_char(timezone('Asia/Seoul', now()), 'YYYY-MM-DD'), 'count', 0),
  adventure_runs jsonb not null default '{"windowStartedAt":0,"count":0}'::jsonb,
  adventure_run jsonb not null default '{"active":false,"currentStage":1,"clearedStages":0,"startedAt":0}'::jsonb,
  mini_games jsonb not null default jsonb_build_object(
    'date', to_char(timezone('Asia/Seoul', now()), 'YYYY-MM-DD'),
    'pointsEarned', 0,
    'pointsEarnedByGame', jsonb_build_object('memory', 0, 'sumTen', 0),
    'plays', 0,
    'bestMemory', 0,
    'bestSumTen', 0
  ),
  world_boss jsonb not null default '{}'::jsonb,
  ex_milestone_claims jsonb not null default '{}'::jsonb,
  shop_transactions integer not null default 0 check (shop_transactions >= 0),
  enhancement_attempts integer not null default 0 check (enhancement_attempts >= 0),
  power_snapshot integer not null default 0 check (power_snapshot >= 0),
  power_snapshot_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gacha_s2_player_cards (
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  card_id text not null,
  copies integer not null check (copies > 0),
  enhancement integer not null default 0 check (enhancement between 0 and 9),
  card_exp integer not null default 0 check (card_exp >= 0),
  locked boolean not null default false,
  first_acquired_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, card_id)
);

create table if not exists public.gacha_s2_idempotency (
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  idempotency_key text not null,
  command_type text not null,
  request_hash text not null check (request_hash ~ '^[0-9a-fA-F]{64}$'),
  response jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (user_id, idempotency_key)
);

create table if not exists public.gacha_s2_import_batches (
  batch_id uuid primary key,
  source_name text not null,
  source_snapshot_at timestamptz,
  source_users integer not null check (source_users >= 0),
  retained_users integer not null check (retained_users >= 0),
  excluded_no_card_users integer not null check (excluded_no_card_users >= 0),
  retained_streamers_without_cards integer not null check (retained_streamers_without_cards >= 0),
  source_bridge_keys integer not null check (source_bridge_keys >= 0),
  retained_bridge_keys integer not null check (retained_bridge_keys >= 0),
  ranking_snapshot_rows integer not null check (ranking_snapshot_rows = 50),
  base_point_total bigint not null check (base_point_total >= 0),
  rank_bonus_total bigint not null check (rank_bonus_total >= 0),
  initial_point_total bigint not null check (initial_point_total >= 0),
  summary jsonb not null,
  imported_at timestamptz not null default now()
);

create index if not exists idx_gacha_s2_accounts_soop_id on public.gacha_s2_accounts(soop_id) where soop_id is not null;
create index if not exists idx_gacha_s2_streamer_bridges_active on public.gacha_s2_streamer_bridges(active, soop_id);
create index if not exists idx_gacha_s2_states_power on public.gacha_s2_player_states(power_snapshot desc, user_id);
create index if not exists idx_gacha_s2_idempotency_expiry on public.gacha_s2_idempotency(expires_at);

alter table public.gacha_s2_accounts enable row level security;
alter table public.gacha_s2_streamer_bridges enable row level security;
alter table public.gacha_s2_player_states enable row level security;
alter table public.gacha_s2_player_cards enable row level security;
alter table public.gacha_s2_idempotency enable row level security;
alter table public.gacha_s2_import_batches enable row level security;

create or replace function public.gacha_s2_preview_season1_import()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with card_totals as (
    select c.user_id, sum(greatest(c.count, 0))::bigint as total_cards
    from public.gacha_collection c
    group by c.user_id
  ), eligible as (
    select u.id, c.total_cards,
      exists (
        select 1 from public.gacha_soop_bridge_keys b
        where b.soop_id = u.soop_id
      ) as is_streamer
    from public.gacha_users u
    left join card_totals c on c.user_id = u.id
    where coalesce(c.total_cards, 0) > 0
      or exists (
        select 1 from public.gacha_soop_bridge_keys b
        where b.soop_id = u.soop_id
      )
  ), ranked as (
    select s.user_id, s.rank::integer as final_rank,
      public.gacha_s2_season1_rank_reward(s.rank::integer) as reward_points
    from public.gacha_season1_final_top50 s
  )
  select jsonb_build_object(
    'sourceUsers', (select count(*) from public.gacha_users),
    'retainedUsers', (select count(*) from eligible),
    'excludedNoCardUsers', (select count(*) from public.gacha_users) - (select count(*) from eligible),
    'excludedNoCardNonStreamerUsers', (select count(*) from public.gacha_users) - (select count(*) from eligible),
    'retainedStreamersWithoutCards', (select count(*) from eligible where is_streamer and coalesce(total_cards, 0) = 0),
    'sourceBridgeKeyRows', (select count(*) from public.gacha_soop_bridge_keys),
    'retainedBridgeKeyRows', (
      select count(*)
      from public.gacha_soop_bridge_keys b
      join public.gacha_users u on u.soop_id = b.soop_id
      join eligible e on e.id = u.id
    ),
    'orphanBridgeKeyRows', (
      select count(*)
      from public.gacha_soop_bridge_keys b
      left join public.gacha_users u on u.soop_id = b.soop_id
      where u.id is null
    ),
    'rankingSnapshotRows', (select count(*) from ranked),
    'invalidRankingRows', (select count(*) from ranked where final_rank not between 1 and 50),
    'distinctRankingRows', (select count(distinct final_rank) from ranked),
    'distinctRankingUsers', (select count(distinct user_id) from ranked),
    'rankingUsersMissingFromSource', (select count(*) from ranked r left join public.gacha_users u on u.id = r.user_id where u.id is null),
    'rankingUsersExcludedNoCards', (select count(*) from ranked r left join eligible e on e.id = r.user_id where e.id is null),
    'basePointTotal', (select count(*) * 5000::bigint from eligible),
    'rankBonusTotal', (select coalesce(sum(r.reward_points), 0)::bigint from ranked r join eligible e on e.id = r.user_id),
    'initialPointTotal', (
      (select count(*) * 5000::bigint from eligible)
      + (select coalesce(sum(r.reward_points), 0)::bigint from ranked r join eligible e on e.id = r.user_id)
    ),
    'sourceCollectionRowsCleared', (select count(*) from public.gacha_collection),
    'sourceCardCopiesCleared', (select coalesce(sum(greatest(count, 0)), 0)::bigint from public.gacha_collection)
  );
$$;

create or replace function public.gacha_s2_import_season1_accounts(
  p_batch_id uuid,
  p_expected_source_users integer,
  p_expected_retained_users integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_preview jsonb;
  v_imported integer;
  v_imported_bridges integer;
  v_existing jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('gacha_s2_import_season1_accounts'));

  select summary into v_existing
  from public.gacha_s2_import_batches
  where batch_id = p_batch_id;
  if found then return v_existing; end if;

  if exists (select 1 from public.gacha_s2_accounts limit 1) then
    raise exception 'season2 accounts already exist; refusing a new import batch';
  end if;

  v_preview := public.gacha_s2_preview_season1_import();
  if (v_preview->>'sourceUsers')::integer <> p_expected_source_users then
    raise exception 'source user count mismatch: expected %, actual %', p_expected_source_users, v_preview->>'sourceUsers';
  end if;
  if (v_preview->>'retainedUsers')::integer <> p_expected_retained_users then
    raise exception 'retained user count mismatch: expected %, actual %', p_expected_retained_users, v_preview->>'retainedUsers';
  end if;
  if (v_preview->>'rankingSnapshotRows')::integer <> 50
    or (v_preview->>'distinctRankingRows')::integer <> 50
    or (v_preview->>'distinctRankingUsers')::integer <> 50
    or (v_preview->>'invalidRankingRows')::integer <> 0
    or (v_preview->>'rankingUsersMissingFromSource')::integer <> 0
    or (v_preview->>'rankingUsersExcludedNoCards')::integer <> 0
    or (v_preview->>'rankBonusTotal')::bigint <> 800000 then
    raise exception 'invalid season1 top50 snapshot: %', v_preview;
  end if;
  if (v_preview->>'orphanBridgeKeyRows')::integer <> 0
    or (v_preview->>'sourceBridgeKeyRows')::integer <> (v_preview->>'retainedBridgeKeyRows')::integer then
    raise exception 'season1 bridge registry cannot be fully migrated: %', v_preview;
  end if;

  with card_totals as (
    select c.user_id, sum(greatest(c.count, 0))::bigint as total_cards
    from public.gacha_collection c
    group by c.user_id
  ), ranked as (
    select s.user_id, s.rank::integer as final_rank
    from public.gacha_season1_final_top50 s
  )
  insert into public.gacha_s2_accounts (
    id, legacy_user_id, nickname, login_key_hash, soop_id, legacy_created_at,
    season1_final_rank, season1_rank_reward_points, is_streamer
  )
  select
    u.id, u.id, trim(u.nickname), u.login_key_hash, nullif(trim(u.soop_id), ''), u.created_at,
    r.final_rank, coalesce(public.gacha_s2_season1_rank_reward(r.final_rank), 0),
    exists (
      select 1 from public.gacha_soop_bridge_keys b
      where b.soop_id = u.soop_id
    )
  from public.gacha_users u
  left join card_totals c on c.user_id = u.id
  left join ranked r on r.user_id = u.id
  where coalesce(c.total_cards, 0) > 0
    or exists (
      select 1 from public.gacha_soop_bridge_keys b
      where b.soop_id = u.soop_id
    );
  get diagnostics v_imported = row_count;

  insert into public.gacha_s2_player_states (user_id, points)
  select a.id, 5000 + a.season1_rank_reward_points
  from public.gacha_s2_accounts a;

  insert into public.gacha_s2_streamer_bridges (
    user_id, soop_id, key_hash, active, legacy_created_at, last_used_at
  )
  select a.id, b.soop_id, b.key_hash, b.active, b.created_at, b.last_used_at
  from public.gacha_soop_bridge_keys b
  join public.gacha_s2_accounts a on a.soop_id = b.soop_id;
  get diagnostics v_imported_bridges = row_count;

  if v_imported <> p_expected_retained_users then
    raise exception 'imported account count mismatch: expected %, actual %', p_expected_retained_users, v_imported;
  end if;
  if v_imported_bridges <> (v_preview->>'sourceBridgeKeyRows')::integer then
    raise exception 'imported bridge count mismatch: expected %, actual %', v_preview->>'sourceBridgeKeyRows', v_imported_bridges;
  end if;
  if exists (select 1 from public.gacha_s2_player_cards) then
    raise exception 'season2 card inventory must be empty after season1 carryover';
  end if;

  insert into public.gacha_s2_import_batches (
    batch_id, source_name, source_snapshot_at, source_users, retained_users,
    excluded_no_card_users, retained_streamers_without_cards, source_bridge_keys, retained_bridge_keys,
    ranking_snapshot_rows, base_point_total,
    rank_bonus_total, initial_point_total, summary
  ) values (
    p_batch_id,
    'season1-final-account-carryover',
    timestamptz '2026-07-18T01:14:01.623Z',
    (v_preview->>'sourceUsers')::integer,
    (v_preview->>'retainedUsers')::integer,
    (v_preview->>'excludedNoCardUsers')::integer,
    (v_preview->>'retainedStreamersWithoutCards')::integer,
    (v_preview->>'sourceBridgeKeyRows')::integer,
    v_imported_bridges,
    (v_preview->>'rankingSnapshotRows')::integer,
    (v_preview->>'basePointTotal')::bigint,
    (v_preview->>'rankBonusTotal')::bigint,
    (v_preview->>'initialPointTotal')::bigint,
    v_preview || jsonb_build_object('batchId', p_batch_id, 'importedUsers', v_imported, 'importedBridgeKeys', v_imported_bridges)
  );

  return v_preview || jsonb_build_object('batchId', p_batch_id, 'importedUsers', v_imported, 'importedBridgeKeys', v_imported_bridges);
end;
$$;

revoke all on table public.gacha_s2_accounts from public, anon, authenticated;
revoke all on table public.gacha_s2_streamer_bridges from public, anon, authenticated;
revoke all on table public.gacha_s2_player_states from public, anon, authenticated;
revoke all on table public.gacha_s2_player_cards from public, anon, authenticated;
revoke all on table public.gacha_s2_idempotency from public, anon, authenticated;
revoke all on table public.gacha_s2_import_batches from public, anon, authenticated;
revoke all on function public.gacha_s2_season1_rank_reward(integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_preview_season1_import() from public, anon, authenticated;
revoke all on function public.gacha_s2_import_season1_accounts(uuid, integer, integer) from public, anon, authenticated;

grant execute on function public.gacha_s2_preview_season1_import() to service_role;
grant execute on function public.gacha_s2_import_season1_accounts(uuid, integer, integer) to service_role;

-- Required operator sequence after this file is reviewed and executed:
-- 1) select public.gacha_s2_preview_season1_import();
-- 2) Verify sourceUsers, retainedUsers, excludedNoCardNonStreamerUsers,
--    retainedStreamersWithoutCards, sourceBridgeKeyRows=retainedBridgeKeyRows,
--    orphanBridgeKeyRows=0, top50=50, and point totals.
-- 3) Only then call gacha_s2_import_season1_accounts with both approved counts.
