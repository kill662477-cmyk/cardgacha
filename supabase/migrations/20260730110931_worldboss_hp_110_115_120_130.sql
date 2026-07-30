-- 2026-07-31 부터 월드보스 체력 17시 110억 / 18시 115억 / 19시 120억 / 20시 130억.
-- 07-30 4회차는 모두 종료(player_damage > 0)라 resync 대상이 아니다.
-- 07-31 17시 회차는 07-30 20:00 에 nextSlot 으로 미리 생성되어 옛 값(95억)을 들고 있다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,slotTiers,17,maxHp}', '11000000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '11500000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '12000000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '13000000000'::jsonb),
      '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb),
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.045'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.091'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.182'::jsonb)
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
