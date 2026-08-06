-- 카드 개성 프로필.
-- 예전에는 카드 ID 해시로 0.97~1.03 스칼라를 전 스탯에 곱했다. 같은 등급·특성이라도
-- 한 장이 다른 장보다 그냥 6% 강한 우열이 됐고, 화면에 표시되지 않아 이유도 알 수 없었다.
--
-- 이제 총합 세기는 거의 같게 두고 배분만 바꾼다. 공격이 높고 물렁한 카드, 공속이 빠른 카드,
-- 치명타가 잦은 카드, 단단한 카드로 갈린다. 종합 편차는 0.93% 이내다.
-- 값은 scripts/tune-card-profiles.mjs 가 계산한다. 손으로 고치지 말 것.
update public.gacha_s2_balance_versions
set config = jsonb_set(config, '{cardProfiles}', $profiles$[
  {"key":"balanced","label":"균형","atk":1,"hp":1,"def":1,"speed":1,"crit":0,"critDamage":0,"scale":1},
  {"key":"power","label":"완력","atk":1.06,"hp":1.01,"def":1.01,"speed":0.97,"crit":0,"critDamage":0,"scale":0.9752},
  {"key":"swift","label":"민첩","atk":0.96,"hp":0.99,"def":0.99,"speed":1.06,"crit":0,"critDamage":0,"scale":0.9867},
  {"key":"precise","label":"정밀","atk":0.98,"hp":1,"def":1,"speed":1,"crit":0.04,"critDamage":0,"scale":1.0004},
  {"key":"fierce","label":"맹공","atk":0.985,"hp":0.99,"def":0.99,"speed":1,"crit":0,"critDamage":0.12,"scale":1.0046},
  {"key":"stout","label":"완강","atk":0.99,"hp":1.05,"def":1.05,"speed":1,"crit":0,"critDamage":0,"scale":1.0012}
]$profiles$::jsonb)
where active;

do $$
declare
  v_cfg jsonb;
  v_profiles jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  v_profiles := v_cfg->'cardProfiles';

  if jsonb_array_length(v_profiles) <> 6 then
    raise exception 'card profiles not applied';
  end if;
  -- 첫 프로필은 보정 없는 기준이어야 한다. 여기가 어긋나면 scale 의 원점이 사라진다.
  if v_profiles->0->>'key' <> 'balanced' or (v_profiles->0->>'scale')::numeric <> 1 then
    raise exception 'baseline profile must be balanced with scale 1';
  end if;
  if (v_profiles->1->>'scale')::numeric <> 0.9752
     or (v_profiles->2->>'scale')::numeric <> 0.9867
     or (v_profiles->5->>'scale')::numeric <> 1.0012 then
    raise exception 'profile scale values not applied';
  end if;

  -- 직전 작업(범용 특성 상향)이 살아 있는지 확인한다.
  if (v_cfg->'archetypes'->'quick'->>'speed')::numeric <> 1.33
     or (v_cfg->'archetypes'->'heavy'->>'atk')::numeric <> 1.35
     or (v_cfg->'archetypes'->'combo'->>'multiHit')::numeric <> 1.15 then
    raise exception 'generalist trait buff lost';
  end if;

  -- 같은 config 컬럼을 다른 작업이 함께 건드린다. 옆 작업 값 보존 확인.
  if (v_cfg->'soopRules'->>'pointsPerBalloon')::numeric <> 100 then
    raise exception 'soop balloon rate lost';
  end if;
  if (v_cfg->'advancedSupportPack'->>'guaranteedTraitRerollPoints')::numeric <> 3000000 then
    raise exception 'advanced pack pity lost';
  end if;
end;
$$;
