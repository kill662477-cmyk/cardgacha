-- 속공/강타/연타는 보스든 잡몹이든 계수가 같은 범용 특성인데, 광역(잡몹 1.5배)과
-- 보스(보스 2배)가 자기 구간에서 압도적이라 65:35 혼합 기준으로 84~89% 에 그쳤다.
-- 유연함이 장점이라 해도 어느 판에서도 최선이 아니면 고를 이유가 없다.
-- 각자 정체성 스탯만 소폭 올려 89~93% 로 당긴다. 격차를 다 메우지는 않는다.
--   속공 speed 1.28 -> 1.33            (혼합 딜 +3.9%)
--   강타 atk 1.31 -> 1.35, crit 0.12 -> 0.14, critDamage 0.2 -> 0.24  (+5.1%)
--   연타 multiHit 1.10 -> 1.15         (+4.5%)
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(
      config,
      '{archetypes,quick}',
      '{"hp":0.94,"atk":0.9,"def":0.9,"crit":0.05,"label":"속공","speed":1.33}'::jsonb),
      '{archetypes,heavy}',
      '{"hp":1.04,"atk":1.35,"def":1,"crit":0.14,"label":"강타","speed":0.78,"critDamage":0.24}'::jsonb),
      '{archetypes,combo}',
      '{"hp":0.96,"atk":0.96,"def":0.94,"label":"연타","speed":1.12,"multiHit":1.15}'::jsonb)
where active;

-- 같은 config 컬럼을 다른 작업이 함께 건드린다. 옆 작업 값이 날아가지 않았는지 확인한다.
do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;

  if (v_cfg->'archetypes'->'quick'->>'speed')::numeric <> 1.33 then
    raise exception 'quick speed not applied';
  end if;
  if (v_cfg->'archetypes'->'heavy'->>'atk')::numeric <> 1.35
     or (v_cfg->'archetypes'->'heavy'->>'crit')::numeric <> 0.14
     or (v_cfg->'archetypes'->'heavy'->>'critDamage')::numeric <> 0.24 then
    raise exception 'heavy values not applied';
  end if;
  if (v_cfg->'archetypes'->'combo'->>'multiHit')::numeric <> 1.15 then
    raise exception 'combo multiHit not applied';
  end if;

  -- 손대지 않은 특성 5종은 그대로여야 한다.
  if (v_cfg->'archetypes'->'area'->>'area')::numeric <> 1.5
     or (v_cfg->'archetypes'->'boss'->>'bossDamage')::numeric <> 2
     or (v_cfg->'archetypes'->'amplify'->>'critAura')::numeric <> 0.15
     or (v_cfg->'archetypes'->'weaken'->>'weaken')::numeric <> 0.15
     or (v_cfg->'archetypes'->'sustain'->>'recovery')::numeric <> 0.08 then
    raise exception 'untouched archetypes were modified';
  end if;

  -- 옆 작업(후원 비율, 고급팩 천장) 값 보존 확인.
  if (v_cfg->'soopRules'->>'pointsPerBalloon')::numeric <> 100 then
    raise exception 'soop balloon rate lost';
  end if;
  if (v_cfg->'advancedSupportPack'->>'guaranteedTraitRerollPoints')::numeric <> 3000000 then
    raise exception 'advanced pack pity lost';
  end if;
end;
$$;
