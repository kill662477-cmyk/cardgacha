-- Card Gacha Season 2: command foundation and server-authoritative formation update.
-- REVIEW ONLY. Run after migrations 001 and 002. Service role only; no direct client writes.

begin;

do $$
begin
  if to_regclass('public.gacha_s2_player_states') is null
    or to_regclass('public.gacha_s2_player_cards') is null
    or to_regclass('public.gacha_s2_card_catalog') is null
    or to_regclass('public.gacha_s2_idempotency') is null then
    raise exception 'missing Season 2 base schema: run migrations 001 and 002 first';
  end if;
end;
$$;

create table if not exists public.gacha_s2_collection_records (
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  card_id text not null references public.gacha_s2_card_catalog(card_id),
  first_acquired_at timestamptz not null default now(),
  primary key (user_id, card_id)
);

create table if not exists public.gacha_s2_command_audit (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  command_id text not null,
  command_type text not null,
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  expected_revision bigint not null check (expected_revision >= 0),
  committed_revision bigint not null check (committed_revision = expected_revision + 1),
  result_code text not null default 'OK',
  created_at timestamptz not null default now(),
  unique (user_id, command_id)
);

create index if not exists idx_gacha_s2_command_audit_user_created
  on public.gacha_s2_command_audit(user_id, created_at desc);

alter table public.gacha_s2_collection_records enable row level security;
alter table public.gacha_s2_command_audit enable row level security;

create or replace function public.gacha_s2_now_ms()
returns bigint
language sql
volatile
as $$
  select floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
$$;

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
    'adventureRun', s.adventure_run,
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
    'miniGameRuns', '[]'::jsonb,
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

create or replace function public.gacha_s2_command_error(
  p_command_id text,
  p_code text,
  p_message text,
  p_revision bigint,
  p_latest_snapshot jsonb default null,
  p_details jsonb default null
) returns jsonb
language sql
volatile
as $$
  select jsonb_build_object(
    'contractVersion', 1,
    'ok', false,
    'commandId', p_command_id,
    'idempotencyKey', p_command_id,
    'code', p_code,
    'message', p_message,
    'retryable', false,
    'serverTime', public.gacha_s2_now_ms(),
    'revision', p_revision,
    'latestSnapshot', p_latest_snapshot,
    'details', p_details
  );
$$;

create or replace function public.gacha_s2_update_formation(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_formation text[]
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_snapshot jsonb;
  v_response jsonb;
  v_card_count integer;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_formation is null or cardinality(p_formation) < 1 or cardinality(p_formation) > 5 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '요청 형식이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null,
      jsonb_build_object('field', 'formation')
    );
  end if;

  if exists (
    select 1 from unnest(p_formation) as ids(card_id)
    where card_id is null or length(trim(card_id)) < 1 or length(card_id) > 80
  ) or (select count(distinct card_id) from unnest(p_formation) as ids(card_id)) <> cardinality(p_formation) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '편성 카드 ID가 올바르지 않습니다.',
      p_expected_revision, null, jsonb_build_object('field', 'formation')
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'updateFormation',
    'expectedRevision', p_expected_revision,
    'formation', to_jsonb(p_formation)
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states
  where user_id = p_user_id
  for update;
  if not found then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.',
      0, null, null
    );
  end if;

  select * into v_previous
  from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'updateFormation' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등성 키를 다른 요청에 사용할 수 없습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;

  if p_expected_revision <> v_revision then
    v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와야 합니다.',
      v_revision, v_snapshot, null
    );
  end if;

  select count(*) into v_card_count
  from public.gacha_s2_player_cards owned
  join public.gacha_s2_card_catalog catalog on catalog.card_id = owned.card_id
  where owned.user_id = p_user_id
    and owned.copies > 0
    and catalog.rarity <> 'EX'
    and owned.card_id = any(p_formation);

  if v_card_count <> cardinality(p_formation) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '미보유 카드나 전투 불가 EX 카드는 편성할 수 없습니다.',
      v_revision, null, jsonb_build_object('field', 'formation')
    );
  end if;

  update public.gacha_s2_player_states
  set formation = p_formation,
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id
  returning revision into v_revision;

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1,
    'ok', true,
    'commandId', p_idempotency_key,
    'idempotencyKey', p_idempotency_key,
    'revision', v_revision,
    'serverTime', public.gacha_s2_now_ms(),
    'serverSeed', 0,
    'snapshot', v_snapshot,
    'result', jsonb_build_object('formation', to_jsonb(p_formation))
  );

  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'updateFormation', v_request_hash, v_response, now() + interval '24 hours'
  );

  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision
  ) values (
    p_user_id, p_idempotency_key, 'updateFormation', v_request_hash, p_expected_revision, v_revision
  );

  return v_response;
end;
$$;

revoke all on table public.gacha_s2_collection_records from public, anon, authenticated;
revoke all on table public.gacha_s2_command_audit from public, anon, authenticated;
revoke all on function public.gacha_s2_now_ms() from public, anon, authenticated;
revoke all on function public.gacha_s2_get_player_snapshot(uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_command_error(text, text, text, bigint, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.gacha_s2_update_formation(uuid, bigint, text, text[]) from public, anon, authenticated;

grant execute on function public.gacha_s2_get_player_snapshot(uuid) to service_role;
grant execute on function public.gacha_s2_update_formation(uuid, bigint, text, text[]) to service_role;

commit;
