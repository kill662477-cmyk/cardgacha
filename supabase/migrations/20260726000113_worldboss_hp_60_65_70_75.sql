-- 월드보스 슬롯 HP 상향: 17시 60억 / 18시 65억 / 19시 70억 / 20시 75억 (직전 55/60/65/70억).
--
-- 사유: 특성 상향(약화·생존·강타·증폭)으로 유저 화력이 전반적으로 올랐다. 각 슬롯 +5억.
-- 서버DPS는 계속 0이다. 처치 여부는 참가자 합산딜 vs max_hp 로만 갈린다.
-- difficultyMultiplier 는 안내 문구 표시 전용이라 17시 대비 HP 비율로 맞춘다.
--
-- 20260725000091 주석대로, config 갱신만으로는 "미리 생성된 다음 슬롯" 행이 옛 HP로 남는다.
-- 실제로 오늘 17시 회차가 55억으로 선생성돼 있어 아래 두 번째 블록에서 함께 리싱크한다.

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
    '{worldBossRules,maxHp}', '6000000000'::jsonb, false),
    '{worldBossRules,slotTiers,17,maxHp}', '6000000000'::jsonb, false),
    '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb, false),
    '{worldBossRules,slotTiers,18,maxHp}', '6500000000'::jsonb, false),
    '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.083'::jsonb, false),
    '{worldBossRules,slotTiers,19,maxHp}', '7000000000'::jsonb, false),
    '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.167'::jsonb, false),
    '{worldBossRules,slotTiers,20,maxHp}', '7500000000'::jsonb, false),
    '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.25'::jsonb, false)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint <> 6000000000
    or (v_cfg->'worldBossRules'->'slotTiers'->'18'->>'maxHp')::bigint <> 6500000000
    or (v_cfg->'worldBossRules'->'slotTiers'->'19'->>'maxHp')::bigint <> 7000000000
    or (v_cfg->'worldBossRules'->'slotTiers'->'20'->>'maxHp')::bigint <> 7500000000 then
    raise exception 'worldboss slot hp update failed';
  end if;
  if (v_cfg->'worldBossRules'->>'maxHp')::bigint <> 6000000000 then
    raise exception 'worldboss default hp update failed';
  end if;
  if (select count(*) from jsonb_each(v_cfg->'worldBossRules'->'slotTiers') as t(k, v)
      where (v->>'serverDamagePerSecond')::bigint <> 0) > 0 then
    raise exception 'worldboss server dps must stay 0';
  end if;
end;
$$;

-- 아직 시작 전(starts_at > now)이고, 아무도 공격하지 않았고(player_damage = 0),
-- 처치되지 않은(defeated_at is null) 행만 새 HP로 갱신한다. 진행 중/종료된 회차는 건드리지 않는다.
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
$$;
