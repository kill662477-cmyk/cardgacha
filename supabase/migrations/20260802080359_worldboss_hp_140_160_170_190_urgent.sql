-- 운영 DB에 실제 적용된 2026-08-02 월드보스 긴급 조정 이력.
-- 17시는 140억 유지, 18/19/20시는 160/170/190억으로 조정한다.
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

  select (config->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint into v_h17
  from public.gacha_s2_balance_versions where active;
  if v_h17 is distinct from 14000000000 then
    raise exception '17:00 slot HP changed unexpectedly: %', v_h17;
  end if;

  select (config#>>'{soopRules,pointsPerBalloon}')::integer into v_balloon
  from public.gacha_s2_balance_versions where active;
  if v_balloon is null then
    raise exception 'soopRules.pointsPerBalloon was lost';
  end if;
end;
$$;
