-- 2026-08-01 부터 월드보스 체력 17시 125억 / 18시 135억 / 19시 145억 / 20시 155억.
-- 대폭 상향: 07-31 회차(110/115/120/130억)가 네 번 다 격파돼 벽 역할을 못 했다.
-- 슬롯 간격도 5억에서 10억으로 벌린다.
--
-- 08-01 17시 회차는 07-31 20:00 에 nextSlot 으로 미리 생성되어 옛 값(110억)을 들고 있다.
-- resync 가 이걸 고친다(starts_at >= now() 이고 player_damage = 0 인 회차만 건드린다).
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,maxHp}', '12500000000'::jsonb),
      '{worldBossRules,slotTiers,17,maxHp}', '12500000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '13500000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '14500000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '15500000000'::jsonb),
      '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb),
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.08'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.16'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.24'::jsonb)
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
