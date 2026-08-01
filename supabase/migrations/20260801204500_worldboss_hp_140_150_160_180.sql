-- 2026-08-02 부터 월드보스 체력 17시 140억 / 18시 150억 / 19시 160억 / 20시 180억.
-- 08-01 회차(125/135/145/155억)도 네 번 다 격파됐다. 초과딜이 회차당 0.05~0.12억뿐이라
-- 아슬아슬해 보이지만 전부 뚫린 이상 벽이 아니다. 20시만 간격을 20억으로 더 벌린다.
--
-- 08-02 17시 회차는 08-01 20:00 에 nextSlot 으로 미리 생성돼 옛 값(125억)을 들고 있다.
-- resync 가 이걸 고친다(starts_at >= now() 이고 player_damage = 0 인 회차만 건드린다).
--
-- jsonb_set 은 worldBossRules 하위 경로만 바꾼다. 같은 config 컬럼의 soopRules
-- (API 후원 비율 작업) 는 건드리지 않으며, 아래 검증에서 값이 살아있는지 확인한다.
update public.gacha_s2_balance_versions
set config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
      config,
      '{worldBossRules,maxHp}', '14000000000'::jsonb),
      '{worldBossRules,slotTiers,17,maxHp}', '14000000000'::jsonb),
      '{worldBossRules,slotTiers,18,maxHp}', '15000000000'::jsonb),
      '{worldBossRules,slotTiers,19,maxHp}', '16000000000'::jsonb),
      '{worldBossRules,slotTiers,20,maxHp}', '18000000000'::jsonb),
      '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb),
      '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.071'::jsonb),
      '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.143'::jsonb),
      '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.286'::jsonb)
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
