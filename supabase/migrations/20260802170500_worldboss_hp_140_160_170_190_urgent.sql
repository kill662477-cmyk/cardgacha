-- 2026-08-02 당일 긴급 조정: 18시 160억 / 19시 170억 / 20시 190억. 17시는 140억 유지.
-- 08-02 17시 회차가 시작 3분 만에 140억이 뚫렸다(17:00 시작, 17:03 격파).
-- 오늘 남은 세 회차를 즉시 올린다.
--
-- 18시 회차는 17:00 에 nextSlot 으로 이미 생성돼 옛 값(150억)을 들고 있다.
-- resync 가 이걸 고친다. 진행이 끝난 17시 회차는 player_damage > 0 이라 건드리지 않는다.
-- 19시·20시 회차는 아직 생성 전이라 아래 config 값으로 만들어진다.
--
-- jsonb_set 은 worldBossRules 하위 경로만 바꾼다. 같은 config 컬럼의 soopRules
-- (API 후원 비율) 는 건드리지 않으며, 아래 검증에서 값이 살아있는지 확인한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,slotTiers,18,maxHp}', '16000000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '17000000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '19000000000'::jsonb),
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.143'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.214'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.357'::jsonb)
where active;

select public.gacha_s2_resync_world_boss_hp(now());

do $$
declare
  v_bad integer;
  v_balloon integer;
  v_h17 bigint;
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

  -- 17시는 이번 조정 대상이 아니다. 실수로 바뀌지 않았는지 확인한다.
  select (config->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint into v_h17
  from public.gacha_s2_balance_versions where active;
  if v_h17 is distinct from 14000000000 then
    raise exception '17:00 slot HP changed unexpectedly: %', v_h17;
  end if;

  -- 다른 작업(API 후원 비율)이 같은 config 를 쓰므로 덮어쓰지 않았는지 확인한다.
  select (config#>>'{soopRules,pointsPerBalloon}')::integer into v_balloon
  from public.gacha_s2_balance_versions where active;
  if v_balloon is null then
    raise exception 'soopRules.pointsPerBalloon was lost';
  end if;
end;
$$;
