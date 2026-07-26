update public.gacha_s2_balance_versions
set config =
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
    config,
    '{worldBossRules,maxHp}', '5500000000'::jsonb, false),
    '{worldBossRules,slotTiers,17,maxHp}', '5500000000'::jsonb, false),
    '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb, false),
    '{worldBossRules,slotTiers,18,maxHp}', '6000000000'::jsonb, false),
    '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.091'::jsonb, false),
    '{worldBossRules,slotTiers,19,maxHp}', '6500000000'::jsonb, false),
    '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.182'::jsonb, false),
    '{worldBossRules,slotTiers,20,maxHp}', '7000000000'::jsonb, false),
    '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.273'::jsonb, false)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint <> 5500000000
    or (v_cfg->'worldBossRules'->'slotTiers'->'18'->>'maxHp')::bigint <> 6000000000
    or (v_cfg->'worldBossRules'->'slotTiers'->'19'->>'maxHp')::bigint <> 6500000000
    or (v_cfg->'worldBossRules'->'slotTiers'->'20'->>'maxHp')::bigint <> 7000000000 then
    raise exception 'worldboss slot hp update failed';
  end if;
  if (v_cfg->'worldBossRules'->>'maxHp')::bigint <> 5500000000 then
    raise exception 'worldboss default hp update failed';
  end if;
  if (select count(*) from jsonb_each(v_cfg->'worldBossRules'->'slotTiers') as t(k, v)
      where (v->>'serverDamagePerSecond')::bigint <> 0) > 0 then
    raise exception 'worldboss server dps must stay 0';
  end if;
end;
$$;

with tier as (
  select
    e.event_id,
    (b.config->'worldBossRules'->'slotTiers'->(((right(e.event_id, 2))::integer)::text)->>'maxHp')::bigint as max_hp,
    (b.config->'worldBossRules'->'slotTiers'->(((right(e.event_id, 2))::integer)::text)->>'serverDamagePerSecond')::bigint as dps
  from public.gacha_s2_world_boss_events e
  cross join (select config from public.gacha_s2_balance_versions where active) b
  where e.starts_at > now()
    and e.player_damage = 0
    and e.defeated_at is null
)
update public.gacha_s2_world_boss_events e
set max_hp = tier.max_hp,
    current_hp = tier.max_hp,
    server_damage_per_second = tier.dps,
    updated_at = now()
from tier
where e.event_id = tier.event_id
  and tier.max_hp is not null
  and tier.dps is not null;

do $$
declare v_stale integer;
begin
  select count(*) into v_stale
  from public.gacha_s2_world_boss_events e
  cross join (select config from public.gacha_s2_balance_versions where active) b
  where e.starts_at > now()
    and e.player_damage = 0
    and e.defeated_at is null
    and (
      e.max_hp is distinct from
        (b.config->'worldBossRules'->'slotTiers'->(((right(e.event_id, 2))::integer)::text)->>'maxHp')::bigint
      or e.server_damage_per_second is distinct from
        (b.config->'worldBossRules'->'slotTiers'->(((right(e.event_id, 2))::integer)::text)->>'serverDamagePerSecond')::bigint
    );
  if v_stale > 0 then
    raise exception 'pending world boss events still stale: %', v_stale;
  end if;
end;
$$;;
