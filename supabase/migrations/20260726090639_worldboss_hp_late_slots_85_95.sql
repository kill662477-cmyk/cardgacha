-- 월드보스 후반 슬롯 대폭 상향: 19시 75억 -> 85억, 20시 80억 -> 95억.
-- 17시(65억) / 18시(70억)는 유지한다.
--
-- 근거: 2026-07-26 18시 회차(70억)가 시작 4분 만에 98.4% 소진됐다(180명, 최대 개인딜 54.8M).
-- 참여가 몰리는 후반 슬롯만 크게 올려 회차별 난이도 경사를 되살린다.
-- 서버DPS는 계속 0이라 처치는 참가자 합산딜 vs max_hp 로만 갈린다.

update public.gacha_s2_balance_versions
set config =
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
    config,
    '{worldBossRules,slotTiers,19,maxHp}', '8500000000'::jsonb, false),
    '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.308'::jsonb, false),
    '{worldBossRules,slotTiers,20,maxHp}', '9500000000'::jsonb, false),
    '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.462'::jsonb, false)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'worldBossRules'->'slotTiers'->'19'->>'maxHp')::bigint <> 8500000000
    or (v_cfg->'worldBossRules'->'slotTiers'->'20'->>'maxHp')::bigint <> 9500000000 then
    raise exception 'late slot hp update failed';
  end if;
  -- 앞 슬롯이 함께 흔들리지 않았는지 확인한다.
  if (v_cfg->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint <> 6500000000
    or (v_cfg->'worldBossRules'->'slotTiers'->'18'->>'maxHp')::bigint <> 7000000000 then
    raise exception 'early slot drifted';
  end if;
  if (select count(*) from jsonb_each(v_cfg->'worldBossRules'->'slotTiers') as t(k, v)
      where (v->>'serverDamagePerSecond')::bigint <> 0) > 0 then
    raise exception 'worldboss server dps must stay 0';
  end if;
end;
$$;

-- 시작 전 + 무공격 + 미처치 회차만 갱신한다. 진행 중인 18시 회차는 starts_at > now() 조건에서 제외된다.
with tier as (
  select
    e.event_id,
    (b.config->'worldBossRules'->'slotTiers'->(((right(e.event_id, 2))::integer)::text)->>'maxHp')::bigint as max_hp
  from public.gacha_s2_world_boss_events e
  cross join (select config from public.gacha_s2_balance_versions where active) b
  where e.starts_at > now()
    and e.player_damage = 0
    and e.defeated_at is null
)
update public.gacha_s2_world_boss_events e
set max_hp = tier.max_hp, current_hp = tier.max_hp, updated_at = now()
from tier
where e.event_id = tier.event_id and tier.max_hp is not null;

do $$
declare v_stale integer;
begin
  select count(*) into v_stale
  from public.gacha_s2_world_boss_events e
  cross join (select config from public.gacha_s2_balance_versions where active) b
  where e.starts_at > now() and e.player_damage = 0 and e.defeated_at is null
    and e.max_hp is distinct from
      (b.config->'worldBossRules'->'slotTiers'->(((right(e.event_id, 2))::integer)::text)->>'maxHp')::bigint;
  if v_stale > 0 then
    raise exception 'pending world boss events still stale: %', v_stale;
  end if;
end;
$$;;
