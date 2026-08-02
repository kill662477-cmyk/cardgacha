-- 2026-08-03 부터 월드보스 체력 17시 220억 / 18시 250억 / 19시 280억 / 20시 340억.
-- 같은 날 앞서 180/210/240/270억으로 잡았으나, 08-02 에 포인트를 과하게 지급해
-- 전체 화력이 예상보다 올라갈 것으로 보고 회차 시작 전에 한 번 더 올린다.
-- 20시는 간격을 60억으로 벌려 마지막 회차를 확실한 벽으로 둔다.
--
-- 08-03 17시 회차는 이미 생성돼 직전 값(180억)을 들고 있다.
-- resync 가 이걸 고친다(starts_at >= now() 이고 player_damage = 0 인 회차만 건드린다).
--
-- jsonb_set 은 worldBossRules 하위 경로만 바꾼다. 같은 config 컬럼의 soopRules
-- (API 후원 비율) 등 다른 작업 영역은 건드리지 않으며, 아래 검증에서 확인한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,maxHp}', '22000000000'::jsonb),
      '{worldBossRules,slotTiers,17,maxHp}', '22000000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '25000000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '28000000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '34000000000'::jsonb),
      '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb),
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.136'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.273'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.545'::jsonb)
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
