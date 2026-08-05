-- 2026-08-05 부터 월드보스 체력 17시 255억 / 18시 265억 / 19시 275억 / 20시 285억.
-- 08-04 는 250/260/270/280억 네 회차 전부 격파됐고 초과딜이 회차당 0.03~0.08억으로 아슬했다.
-- 성장분만큼만 따라가도록 전 회차 +5억.
--
-- 08-05 17시 회차는 08-04 20:00 에 미리 생성돼 옛 값(250억)을 들고 있다.
-- resync 가 이걸 고친다(starts_at >= now() 이고 player_damage = 0 인 회차만 건드린다).
--
-- jsonb_set 은 worldBossRules 하위 경로만 바꾼다. 같은 config 컬럼의 다른 작업 영역
-- (soopRules 후원 비율, advancedSupportPack 확정 지급 임계값)은 건드리지 않으며 아래에서 확인한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,maxHp}', '25500000000'::jsonb),
      '{worldBossRules,slotTiers,17,maxHp}', '25500000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '26500000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '27500000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '28500000000'::jsonb),
      '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb),
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.039'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.078'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.118'::jsonb)
where active;

select public.gacha_s2_resync_world_boss_hp(now());

do $$
declare
  v_bad integer;
  v_balloon integer;
  v_pity bigint;
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

  -- 같은 config 를 쓰는 다른 작업 영역이 살아있는지 확인한다.
  select (config#>>'{soopRules,pointsPerBalloon}')::integer,
         (config->'advancedSupportPack'->>'guaranteedTraitRerollPoints')::bigint
  into v_balloon, v_pity
  from public.gacha_s2_balance_versions where active;
  if v_balloon is null then
    raise exception 'soopRules.pointsPerBalloon was lost';
  end if;
  if v_pity is distinct from 3000000 then
    raise exception 'advanced pack pity threshold changed: %', v_pity;
  end if;
end;
$$;
