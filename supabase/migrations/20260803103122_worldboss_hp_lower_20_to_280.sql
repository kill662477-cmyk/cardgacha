-- 2026-08-03 당일 하향 2: 20시 300억 -> 280억. 17시(250억)·18시·19시(각 280억)는 유지.
-- 08-03 실측: 17시 250억 21분 격파, 18시 280억 273.4억(97.65%) 실패, 19시 280억 268.0억(95.7%) 실패.
-- 네 회차 모두 같은 계단(250/280/280/280)이 된다.
--
-- 20시 회차는 19:00 에 이미 생성돼 옛 값(300억)을 들고 있다. resync 가 이걸 고친다.
-- 진행이 끝난 17~19시 회차는 player_damage > 0 이라 건드리지 않는다.
--
-- jsonb_set 은 worldBossRules 하위 경로만 바꾼다. 같은 config 컬럼의 soopRules
-- (API 후원 비율) 등 다른 작업 영역은 건드리지 않으며, 아래 검증에서 확인한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(
      config,
      '{worldBossRules,slotTiers,20,maxHp}', '28000000000'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.12'::jsonb)
where active;

select public.gacha_s2_resync_world_boss_hp(now());

do $$
declare
  v_bad integer;
  v_balloon integer;
  v_h17 bigint;
  v_h18 bigint;
  v_h19 bigint;
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

  -- 17~19시는 이번 조정 대상이 아니다. 실수로 바뀌지 않았는지 확인한다.
  select (config->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint,
         (config->'worldBossRules'->'slotTiers'->'18'->>'maxHp')::bigint,
         (config->'worldBossRules'->'slotTiers'->'19'->>'maxHp')::bigint
  into v_h17, v_h18, v_h19
  from public.gacha_s2_balance_versions where active;
  if v_h17 is distinct from 25000000000
    or v_h18 is distinct from 28000000000
    or v_h19 is distinct from 28000000000 then
    raise exception 'earlier slot HP changed unexpectedly: 17=% 18=% 19=%', v_h17, v_h18, v_h19;
  end if;

  -- 다른 작업(API 후원 비율)이 같은 config 를 쓰므로 덮어쓰지 않았는지 확인한다.
  select (config#>>'{soopRules,pointsPerBalloon}')::integer into v_balloon
  from public.gacha_s2_balance_versions where active;
  if v_balloon is null then
    raise exception 'soopRules.pointsPerBalloon was lost';
  end if;
end;
$$;
