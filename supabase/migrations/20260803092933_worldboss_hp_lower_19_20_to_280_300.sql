-- 2026-08-03 당일 하향: 19시 310억 -> 280억, 20시 350억 -> 300억. 17시(250억)·18시(280억)는 유지.
-- 08-03 실측: 17시 250억은 21분 만에 격파(적정), 18시 280억은 마감 1분 전 97.65% 로 실패 직전.
-- 뒤 회차가 그대로면 연속 실패가 확정적이라 19시 시작 전에 낮춘다.
-- 결과적으로 18시와 19시가 같은 280억이 되고 20시만 300억으로 소폭 높다.
--
-- 19시 회차는 이미 생성돼 옛 값(310억)을 들고 있다. resync 가 이걸 고친다.
-- 진행이 끝난 17시·18시 회차는 player_damage > 0 이라 건드리지 않는다.
-- 20시 회차는 아직 생성 전이라 아래 config 값으로 만들어진다.
--
-- jsonb_set 은 worldBossRules 하위 경로만 바꾼다. 같은 config 컬럼의 soopRules
-- (API 후원 비율) 등 다른 작업 영역은 건드리지 않으며, 아래 검증에서 확인한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,slotTiers,19,maxHp}', '28000000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '30000000000'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.12'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.2'::jsonb)
where active;

select public.gacha_s2_resync_world_boss_hp(now());

do $$
declare
  v_bad integer;
  v_balloon integer;
  v_h17 bigint;
  v_h18 bigint;
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

  -- 17시·18시는 이번 조정 대상이 아니다. 실수로 바뀌지 않았는지 확인한다.
  select (config->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint,
         (config->'worldBossRules'->'slotTiers'->'18'->>'maxHp')::bigint
  into v_h17, v_h18
  from public.gacha_s2_balance_versions where active;
  if v_h17 is distinct from 25000000000 or v_h18 is distinct from 28000000000 then
    raise exception 'early slot HP changed unexpectedly: 17=% 18=%', v_h17, v_h18;
  end if;

  -- 다른 작업(API 후원 비율)이 같은 config 를 쓰므로 덮어쓰지 않았는지 확인한다.
  select (config#>>'{soopRules,pointsPerBalloon}')::integer into v_balloon
  from public.gacha_s2_balance_versions where active;
  if v_balloon is null then
    raise exception 'soopRules.pointsPerBalloon was lost';
  end if;
end;
$$;
