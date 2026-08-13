-- 2026-08-13 월드보스 체력 네 회차 모두 20억씩 상향.
--   17시 275 -> 295억 / 18시 285 -> 305억 / 19시 295 -> 315억 / 20시 305 -> 325억
-- difficultyMultiplier 는 표시용이며 17시 대비 비율에 맞춰 다시 계산했다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,slotTiers,17,maxHp}', '29500000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '30500000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '31500000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '32500000000'::jsonb),
      '{worldBossRules,maxHp}', '29500000000'::jsonb)
where active;

update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.034'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.068'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.102'::jsonb)
where active;

-- 아직 시작하지 않았고 피해가 0인 회차에만 새 체력을 적용한다.
select public.gacha_s2_resync_world_boss_hp(now());

do $$
declare
  v_rules jsonb;
  v_bad integer;
begin
  select config->'worldBossRules' into v_rules from public.gacha_s2_balance_versions where active;

  if (v_rules->'slotTiers'->'17'->>'maxHp')::bigint <> 29500000000
     or (v_rules->'slotTiers'->'18'->>'maxHp')::bigint <> 30500000000
     or (v_rules->'slotTiers'->'19'->>'maxHp')::bigint <> 31500000000
     or (v_rules->'slotTiers'->'20'->>'maxHp')::bigint <> 32500000000 then
    raise exception 'world boss hp not applied';
  end if;
  if (v_rules->>'maxHp')::bigint <> 29500000000 then
    raise exception 'default maxHp not applied';
  end if;

  -- 경로를 slots 로 잘못 잡으면 엉뚱한 키가 생기고 slotTiers 는 옛 값으로 남는다.
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

  if (select (config->'soopRules'->>'pointsPerBalloon')::numeric
      from public.gacha_s2_balance_versions where active) <> 100 then
    raise exception 'soop balloon rate lost';
  end if;
end;
$$;
