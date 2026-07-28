-- 2026-07-29 부터 월드보스 체력 17시 85억 / 18시 90억 / 19시 95억 / 20시 105억.
--
-- 07-28 4회차는 모두 종료됐으므로(player_damage > 0) resync 대상이 아니다.
-- 07-29 17시 회차는 07-28 20:00 에 nextSlot 으로 미리 생성되어 옛 값(75억)을 들고 있었다.
-- 바로 이 구멍이 07-28 17시가 65억으로 열린 사고의 원인이었으므로,
-- 설정 변경 뒤 반드시 resync 를 돌리고 어긋난 회차가 남았는지 검증한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,slotTiers,17,maxHp}', '8500000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '9000000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '9500000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '10500000000'::jsonb),
      '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb),
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.059'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.118'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.235'::jsonb)
where active;

select public.gacha_s2_resync_world_boss_hp(now());

do $$
declare v_bad integer;
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
end;
$$;
