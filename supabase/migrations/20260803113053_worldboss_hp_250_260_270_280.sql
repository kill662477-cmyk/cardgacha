-- 2026-08-04 부터 월드보스 체력 17시 250억 / 18시 260억 / 19시 270억 / 20시 280억.
-- 08-03 실측: 17시 250억 21분 격파, 18시 280억 273.4억 실패, 19시 280억 268.0억 실패,
-- 20시 280억 280.2억 격파. 280억이 경계선이라 앞 회차를 완만하게 낮춰 10억 계단으로 만든다.
--
-- 08-04 17시 회차는 이미 생성돼 있고 값(250억)이 새 설정과 같아 변화 없다.
-- resync 는 starts_at >= now() 이고 player_damage = 0 인 회차만 건드린다.
--
-- jsonb_set 은 worldBossRules 하위 경로만 바꾼다. 같은 config 컬럼의 soopRules
-- (API 후원 비율) 등 다른 작업 영역은 건드리지 않으며, 아래 검증에서 확인한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,maxHp}', '25000000000'::jsonb),
      '{worldBossRules,slotTiers,17,maxHp}', '25000000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '26000000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '27000000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '28000000000'::jsonb),
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.04'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.08'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.12'::jsonb)
where active;

select public.gacha_s2_resync_world_boss_hp(now());

do $$
declare
  v_bad integer;
  v_balloon integer;
begin
  select count(*) into v_bad
  from public.gacha_s2_world_boss_events w
  join public.gacha_s2_balance_versions b on b.active
  where w.starts_at >= now()
    and w.max_hp is distinct from
        (b.config->'worldBossRules'->'slotTiers'->((right(w.event_id, 2))::integer)::text->>'maxHp')::bigint;
  if v_bad > 0 then
    raise exception 'pending world boss rounds still out of sync: %', v_bad;
  end if;

  -- 다른 작업(API 후원 비율)이 같은 config 를 쓰므로 덮어쓰지 않았는지 확인한다.
  select (config#>>'{soopRules,pointsPerBalloon}')::integer into v_balloon
  from public.gacha_s2_balance_versions where active;
  if v_balloon is null then
    raise exception 'soopRules.pointsPerBalloon was lost';
  end if;
end;
$$;
