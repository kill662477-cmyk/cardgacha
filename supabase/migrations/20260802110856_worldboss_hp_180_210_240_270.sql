-- 2026-08-03 부터 월드보스 체력 17시 180억 / 18시 210억 / 19시 240억 / 20시 270억.
-- 08-02 는 당일 긴급 상향(140/160/170/190억)까지 네 회차 전부 격파됐다.
-- 슬롯 간격을 10~20억에서 30억으로 크게 벌린다.
--
-- 08-03 17시 회차는 08-02 20:00 에 nextSlot 으로 미리 생성돼 옛 값(140억)을 들고 있다.
-- resync 가 이걸 고친다(starts_at >= now() 이고 player_damage = 0 인 회차만 건드린다).
--
-- jsonb_set 은 worldBossRules 하위 경로만 바꾼다. 같은 config 컬럼의 soopRules
-- (API 후원 비율) 등 다른 작업 영역은 건드리지 않으며, 아래 검증에서 확인한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,maxHp}', '18000000000'::jsonb),
      '{worldBossRules,slotTiers,17,maxHp}', '18000000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '21000000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '24000000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '27000000000'::jsonb),
      '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb),
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.167'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.333'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.5'::jsonb)
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
