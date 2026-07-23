-- Time-slot world-boss tiers and an atomic 10-energy attack cost.

begin;

insert into public.gacha_s2_balance_versions (
  version, config_hash, catalog_hash, config, active, activated_at
)
select
  '2026.07.22-worldboss-tiers-1',
  '2baaf80c5825d506e015c0b5030669aaa63bdc558caae3f5c6d96837bc509a4a',
  catalog_hash,
  jsonb_set(
    jsonb_set(
      jsonb_set(
        config,
        '{balanceVersion}',
        to_jsonb('2026.07.22-worldboss-tiers-1'::text),
        true
      ),
      '{worldBossRules,attackEnergyCost}',
      '10'::jsonb,
      true
    ),
    '{worldBossRules,slotTiers}',
    $tiers${
      "17":{"title":"신호 요새","name":"SIGNAL//BASTION","difficultyMultiplier":1,"maxHp":5000000000,"serverDamagePerSecond":2766667,"image":"assets/renewal/worldboss/boss-17-signal-bastion.webp"},
      "18":{"title":"중계 포식자","name":"RELAY//DEVOURER","difficultyMultiplier":1.25,"maxHp":6250000000,"serverDamagePerSecond":3455555,"image":"assets/renewal/worldboss/boss-18-relay-devourer.webp"},
      "19":{"title":"공허 수확자","name":"VOID//HARVESTER","difficultyMultiplier":1.6,"maxHp":8000000000,"serverDamagePerSecond":4419444,"image":"assets/renewal/worldboss/boss-19-void-harvester.webp"},
      "20":{"title":"악의 특이점","name":"MALICE//SINGULARITY","difficultyMultiplier":2,"maxHp":10000000000,"serverDamagePerSecond":5516666,"image":"assets/renewal/worldboss/boss-20-malice-singularity.webp"}
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

update public.gacha_s2_balance_versions
set active = false
where active;

update public.gacha_s2_balance_versions
set active = true,
    activated_at = now()
where version = '2026.07.22-worldboss-tiers-1';

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
  v_hour text;
  v_tier jsonb;
  v_max_hp bigint;
  v_server_damage_per_second bigint;
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
    v_hour := ((right(v_slot->>'eventId', 2))::integer)::text;
    v_tier := v_config->'worldBossRules'->'slotTiers'->v_hour;
    v_max_hp := coalesce(
      (v_tier->>'maxHp')::bigint,
      (v_config->'worldBossRules'->>'maxHp')::bigint
    );
    v_server_damage_per_second := coalesce(
      (v_tier->>'serverDamagePerSecond')::bigint,
      (v_config->'worldBossRules'->>'serverDamagePerSecond')::bigint
    );
    insert into public.gacha_s2_world_boss_events (
      event_id, balance_version, starts_at, raid_ends_at, ends_at,
      max_hp, current_hp, server_damage_per_second
    ) values (
      v_slot->>'eventId',
      v_version,
      to_timestamp((v_slot->>'startsAt')::numeric / 1000.0),
      to_timestamp((v_slot->>'raidEndsAt')::numeric / 1000.0),
      to_timestamp((v_slot->>'endsAt')::numeric / 1000.0),
      v_max_hp,
      v_max_hp,
      v_server_damage_per_second
    ) on conflict (event_id) do nothing;
  end loop;
  return v_schedule;
end;
$$;

-- A status read during the previous slot can pre-create the next event. Retier
-- only untouched, future events; never change an active or completed raid.
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

do $migration$
declare
  v_signature regprocedure := 'public.gacha_s2_attack_world_boss(uuid,bigint,text,text,bigint,text)'::regprocedure;
  v_definition text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(v_signature) into v_definition;

  v_old := E'  v_revision bigint;';
  v_new := E'  v_revision bigint;\n  v_energy integer;\n  v_max_energy integer;\n  v_last_energy_at timestamptz;\n  v_interval_ms bigint;\n  v_recovered integer;\n  v_energy_cost integer;';
  if strpos(v_definition, v_old) = 0 then raise exception 'world-boss energy declaration patch target missing'; end if;
  v_definition := replace(v_definition, v_old, v_new);

  v_old := E'  select revision into v_revision\n  from public.gacha_s2_player_states\n  where user_id = p_user_id\n  for update;';
  v_new := E'  select revision, action_energy, max_action_energy, last_energy_at\n  into v_revision, v_energy, v_max_energy, v_last_energy_at\n  from public.gacha_s2_player_states\n  where user_id = p_user_id\n  for update;';
  if strpos(v_definition, v_old) = 0 then raise exception 'world-boss energy lock patch target missing'; end if;
  v_definition := replace(v_definition, v_old, v_new);

  v_old := E'  v_battle_seconds := (v_config->''worldBossRules''->>''battleDuration'')::integer;';
  v_new := E'  v_battle_seconds := (v_config->''worldBossRules''->>''battleDuration'')::integer;\n  v_interval_ms := (v_config->''rewardRules''->>''energyRecoveryMinutes'')::bigint * 60000;\n  if v_energy < v_max_energy then\n    v_recovered := floor(greatest(0, extract(epoch from (v_now - v_last_energy_at)) * 1000) / v_interval_ms)::integer;\n    v_energy := least(v_max_energy, v_energy + v_recovered);\n  end if;\n  v_energy_cost := coalesce((v_config->''worldBossRules''->>''attackEnergyCost'')::integer, 10);\n  if v_energy < v_energy_cost then\n    return public.gacha_s2_command_error(p_idempotency_key, ''COMMAND_REJECTED'', ''행동력이 부족합니다.'', v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);\n  end if;';
  if strpos(v_definition, v_old) = 0 then raise exception 'world-boss energy validation patch target missing'; end if;
  v_definition := replace(v_definition, v_old, v_new);

  v_old := E'  set world_boss = v_progress,\n      revision = revision + 1,';
  v_new := E'  set world_boss = v_progress,\n      action_energy = v_energy - v_energy_cost,\n      last_energy_at = v_now,\n      revision = revision + 1,';
  if strpos(v_definition, v_old) = 0 then raise exception 'world-boss energy debit patch target missing'; end if;
  v_definition := replace(v_definition, v_old, v_new);

  execute v_definition;
end;
$migration$;

revoke all on function public.gacha_s2_ensure_world_boss_schedule(timestamptz) from public, anon, authenticated;
grant execute on function public.gacha_s2_ensure_world_boss_schedule(timestamptz) to service_role;
revoke all on function public.gacha_s2_attack_world_boss(uuid, bigint, text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_attack_world_boss(uuid, bigint, text, text, bigint, text) to service_role;

commit;
