-- 운영에 적용된 20260813124304 이력을 Git에 동일 버전으로 복구한다.
-- 월드보스 체력 네 회차 모두 10억씩 상향.
--   17시 295 -> 305억 / 18시 305 -> 315억 / 19시 315 -> 325억 / 20시 325 -> 335억
--
-- 2026-08-13 네 회차가 전부 격파됐다(초과딜 0.1~0.2억). 계단 간격은 맞았으므로
-- 전체를 같은 폭으로 올린다. difficultyMultiplier 는 표시용이며 17시 대비 비율에 맞췄다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,slotTiers,17,maxHp}', '30500000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '31500000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '32500000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '33500000000'::jsonb),
      '{worldBossRules,maxHp}', '30500000000'::jsonb)
where active;

update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.033'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.066'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.098'::jsonb)
where active;

-- 아직 시작하지 않았고 피해가 0인 회차에만 새 체력을 적용한다.
-- 이미 끝난 회차는 gacha_s2_resync_world_boss_hp 가 조건으로 걸러 낸다.
select public.gacha_s2_resync_world_boss_hp(now());

do $$
declare
  v_rules jsonb;
  v_bad integer;
begin
  select config->'worldBossRules' into v_rules from public.gacha_s2_balance_versions where active;

  if (v_rules->'slotTiers'->'17'->>'maxHp')::bigint <> 30500000000
     or (v_rules->'slotTiers'->'18'->>'maxHp')::bigint <> 31500000000
     or (v_rules->'slotTiers'->'19'->>'maxHp')::bigint <> 32500000000
     or (v_rules->'slotTiers'->'20'->>'maxHp')::bigint <> 33500000000 then
    raise exception 'world boss hp not applied';
  end if;
  if (v_rules->>'maxHp')::bigint <> 30500000000 then
    raise exception 'default maxHp not applied';
  end if;

  if jsonb_typeof(v_rules->'slotTiers') <> 'object'
     or (select count(*) from jsonb_object_keys(v_rules->'slotTiers')) <> 4 then
    raise exception 'slotTiers shape broken';
  end if;
  if (v_rules->'slotTiers'->'17'->>'title') is null
     or (v_rules->'slotTiers'->'20'->>'image') is null then
    raise exception 'slot metadata lost';
  end if;
  if v_rules ? 'slots' then
    raise exception 'stray slots key created';
  end if;

  select count(*) into v_bad
  from public.gacha_s2_world_boss_events e
  where e.starts_at > now() and e.player_damage = 0
    and e.max_hp <> (v_rules->'slotTiers'
      ->(extract(hour from e.starts_at at time zone 'Asia/Seoul')::integer::text)->>'maxHp')::bigint;
  if v_bad > 0 then
    raise exception 'pending world boss events not resynced: % rows', v_bad;
  end if;

  -- 피해가 쌓인 회차는 체력이 그대로여야 한다. 오늘 끝난 세 회차로 확인한다.
  -- (값만 비교하면 과거에 우연히 같은 체력이던 회차까지 걸리므로 회차를 특정한다.)
  select count(*) into v_bad
  from public.gacha_s2_world_boss_events e
  where e.event_id in ('noise-zero-20260813-18', 'noise-zero-20260813-19', 'noise-zero-20260813-20')
    and e.max_hp <> case right(e.event_id, 2)
      when '18' then 30500000000 when '19' then 31500000000 else 32500000000 end;
  if v_bad > 0 then
    raise exception 'finished events were modified: % rows', v_bad;
  end if;

  if (select (config->'soopRules'->>'pointsPerBalloon')::numeric
      from public.gacha_s2_balance_versions where active) <> 100 then
    raise exception 'soop balloon rate lost';
  end if;
end;
$$;
