-- Escalate each world-boss time slot by 1.5x and grant a clear-only guard roll.

begin;

alter table public.gacha_s2_world_boss_players
  add column if not exists bonus_item_ids jsonb not null default '[]'::jsonb;

alter table public.gacha_s2_world_boss_players
  drop constraint if exists gacha_s2_world_boss_players_bonus_item_ids_check;
alter table public.gacha_s2_world_boss_players
  add constraint gacha_s2_world_boss_players_bonus_item_ids_check
  check (jsonb_typeof(bonus_item_ids) = 'array');

update public.gacha_s2_world_boss_players
set bonus_item_ids = case
  when bonus_item_id is null then '[]'::jsonb
  else jsonb_build_array(bonus_item_id)
end
where bonus_item_ids = '[]'::jsonb
  and bonus_item_id is not null;

insert into public.gacha_s2_balance_versions (
  version, config_hash, catalog_hash, config, active, activated_at
)
select
  '2026.07.22-worldboss-escalation-1',
  '29c0bd2e9ffcb91a97c4800f01d13f5ee947626990d1dc448ca2a096c822d29f',
  catalog_hash,
  jsonb_set(
    jsonb_set(
      config,
      '{balanceVersion}',
      to_jsonb('2026.07.22-worldboss-escalation-1'::text),
      true
    ),
    '{worldBossRules,slotTiers}',
    $tiers${
      "17":{"title":"신호 요새","name":"SIGNAL//BASTION","difficultyMultiplier":1,"maxHp":5000000000,"serverDamagePerSecond":2766667,"clearDestructionGuardRate":0.05,"image":"assets/renewal/worldboss/boss-17-signal-bastion.webp"},
      "18":{"title":"중계 포식자","name":"RELAY//DEVOURER","difficultyMultiplier":1.5,"maxHp":7500000000,"serverDamagePerSecond":4150001,"clearDestructionGuardRate":0.10,"image":"assets/renewal/worldboss/boss-18-relay-devourer.webp"},
      "19":{"title":"공허 수확자","name":"VOID//HARVESTER","difficultyMultiplier":2.25,"maxHp":11250000000,"serverDamagePerSecond":6225001,"clearDestructionGuardRate":0.15,"image":"assets/renewal/worldboss/boss-19-void-harvester.webp"},
      "20":{"title":"악의 특이점","name":"MALICE//SINGULARITY","difficultyMultiplier":3.375,"maxHp":16875000000,"serverDamagePerSecond":9337501,"clearDestructionGuardRate":0.20,"image":"assets/renewal/worldboss/boss-20-malice-singularity.webp"}
    }$tiers$::jsonb,
    true
  ),
  false,
  now()
from public.gacha_s2_balance_versions
where active
on conflict (version) do update
set config_hash = excluded.config_hash,
    catalog_hash = excluded.catalog_hash,
    config = excluded.config,
    activated_at = excluded.activated_at;

update public.gacha_s2_balance_versions set active = false where active;
update public.gacha_s2_balance_versions
set active = true, activated_at = now()
where version = '2026.07.22-worldboss-escalation-1';

-- A previous status request can create the next event early. Only retier an
-- untouched future event; current and completed raids keep their old values.
with active_balance as (
  select version, config
  from public.gacha_s2_balance_versions
  where active
), future_tiers as (
  select
    event.event_id,
    balance.version,
    (balance.config->'worldBossRules'->'slotTiers'->(((right(event.event_id, 2))::integer)::text)->>'maxHp')::bigint as max_hp,
    (balance.config->'worldBossRules'->'slotTiers'->(((right(event.event_id, 2))::integer)::text)->>'serverDamagePerSecond')::bigint as server_damage_per_second
  from public.gacha_s2_world_boss_events event
  cross join active_balance balance
  where event.starts_at > now()
    and event.player_damage = 0
    and not exists (
      select 1 from public.gacha_s2_world_boss_attempts attempt
      where attempt.event_id = event.event_id
    )
)
update public.gacha_s2_world_boss_events event
set balance_version = tier.version,
    max_hp = tier.max_hp,
    current_hp = tier.max_hp,
    server_damage_per_second = tier.server_damage_per_second,
    updated_at = now()
from future_tiers tier
where event.event_id = tier.event_id
  and tier.max_hp is not null
  and tier.server_damage_per_second is not null;

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
  v_slot_tier jsonb;
  v_tier_index integer;
  v_defeated boolean;
  v_points integer;
  v_seed bigint;
  v_bonus_item text;
  v_bonus_item_ids jsonb := '[]'::jsonb;
  v_guard_rate numeric := 0;
  v_award_item text;
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
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등 키를 다른 요청에 사용할 수 없습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와 주세요.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null
    );
  end if;
  v_schedule := public.gacha_s2_ensure_world_boss_schedule(v_now);
  if (v_schedule->'currentSlot'->>'eventId') is distinct from p_event_id then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '현재 결과 공개 중인 월드보스가 아닙니다.', v_revision, null, null);
  end if;
  v_event := public.gacha_s2_sync_world_boss_event(p_event_id, v_now);
  if v_event.event_id is null or v_now < v_event.raid_ends_at or v_now >= v_event.ends_at then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '결과 공개 시간에만 보상을 받을 수 있습니다.', v_revision, null, null);
  end if;
  select * into v_player
  from public.gacha_s2_world_boss_players
  where event_id = p_event_id and user_id = p_user_id
  for update;
  if not found or v_player.attempts = 0 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '이번 월드보스 참여 기록이 없습니다.', v_revision, null, null);
  end if;
  if v_player.claimed_at is not null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '이미 이번 월드보스 보상을 받았습니다.', v_revision, null, null);
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
  v_points := case when v_defeated then (v_tier->>'points')::integer else (v_tier->>'failurePoints')::integer end;
  v_seed := public.gacha_s2_new_seed();
  v_bonus_item := public.gacha_s2_roll_world_boss_drop(v_config, v_defeated, v_seed, 20);
  if v_bonus_item is not null then
    v_bonus_item_ids := v_bonus_item_ids || jsonb_build_array(v_bonus_item);
  end if;
  v_slot_tier := v_config->'worldBossRules'->'slotTiers'->(((right(p_event_id, 2))::integer)::text);
  v_guard_rate := greatest(0, least(1, coalesce((v_slot_tier->>'clearDestructionGuardRate')::numeric, 0)));
  if v_defeated
    and not (v_bonus_item_ids ? 'destructionGuard')
    and public.gacha_s2_seed_roll(v_seed, 30) < v_guard_rate then
    v_bonus_item_ids := v_bonus_item_ids || jsonb_build_array('destructionGuard');
  end if;
  for v_award_item in
    select value from jsonb_array_elements_text(v_bonus_item_ids) as awards(value)
  loop
    v_support_items := jsonb_set(
      v_support_items, array[v_award_item],
      to_jsonb(coalesce((v_support_items->>v_award_item)::integer, 0) + 1), true
    );
  end loop;
  update public.gacha_s2_world_boss_players
  set claimed_tier = v_tier_index,
      reward_points = v_points,
      bonus_item_id = v_bonus_item,
      bonus_item_ids = v_bonus_item_ids,
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
      'bonusItemId', v_bonus_item,
      'bonusItemIds', v_bonus_item_ids,
      'destructionGuardAwarded', v_bonus_item_ids ? 'destructionGuard'
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

revoke all on function public.gacha_s2_claim_world_boss_reward(uuid, bigint, text, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_claim_world_boss_reward(uuid, bigint, text, text) to service_role;

commit;
