-- 2026-08-03 부터 월드보스 체력 17시 250억 / 18시 280억 / 19시 310억 / 20시 350억.
-- 같은 날 220/250/280/340억으로 잡았던 것을 회차 시작 전에 다시 올린다.
-- 08-02 포인트 대량 지급분이 화력으로 얼마나 전환될지 불확실해 앞 회차를 더 두껍게 잡는다.
-- 간격은 30/30/40억.
--
-- 08-03 17시 회차는 이미 생성돼 직전 값(220억)을 들고 있다.
-- resync 가 이걸 고친다(starts_at >= now() 이고 player_damage = 0 인 회차만 건드린다).
--
-- jsonb_set 은 worldBossRules 하위 경로만 바꾼다. 같은 config 컬럼의 soopRules
-- (API 후원 비율) 등 다른 작업 영역은 건드리지 않으며, 아래 검증에서 확인한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,maxHp}', '25000000000'::jsonb),
      '{worldBossRules,slotTiers,17,maxHp}', '25000000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '28000000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '31000000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '35000000000'::jsonb),
      '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb),
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.12'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.24'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.4'::jsonb)
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
