-- 보스 특성 2.0 상향 후 Hell10을 최종 콘텐츠 기준으로 재조정하고
-- 월드보스 슬롯별 공동 체력을 110/115/120/130억으로 올린다.
-- 전체 HELL을 한 편성으로 통과할 수 있는 SSS 9강·올도감·길드 Lv.10 조합이
-- 제한시간 끝자락에 클리어하고, 길드/도감 누락과 SSS 8강은 실패하는 기준이다.
begin;

do $hell10_retune$
declare
  v_config jsonb;
  v_hash text;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active;

  if v_config is null then
    raise exception 'active balance config missing';
  end if;

  v_config := jsonb_set(
    v_config,
    '{balanceVersion}',
    '"2026.07.30-hell10-worldboss-retune-1"'::jsonb,
    true
  );
  v_config := jsonb_set(v_config, '{regions,10,bossHp}', '48000000'::jsonb, false);
  v_config := jsonb_set(v_config, '{regions,10,bossAttack}', '50000'::jsonb, false);
  v_config := jsonb_set(v_config, '{stages,109,enemyHp}', '48000000'::jsonb, false);
  v_config := jsonb_set(v_config, '{stages,109,enemyAttack}', '50000'::jsonb, false);
  v_config := jsonb_set(v_config, '{worldBossRules,maxHp}', '11000000000'::jsonb, false);
  v_config := jsonb_set(v_config, '{worldBossRules,slotTiers,17,maxHp}', '11000000000'::jsonb, false);
  v_config := jsonb_set(v_config, '{worldBossRules,slotTiers,18,maxHp}', '11500000000'::jsonb, false);
  v_config := jsonb_set(v_config, '{worldBossRules,slotTiers,19,maxHp}', '12000000000'::jsonb, false);
  v_config := jsonb_set(v_config, '{worldBossRules,slotTiers,20,maxHp}', '13000000000'::jsonb, false);
  v_config := jsonb_set(v_config, '{worldBossRules,slotTiers,17,difficultyMultiplier}', '1'::jsonb, false);
  v_config := jsonb_set(v_config, '{worldBossRules,slotTiers,18,difficultyMultiplier}', '1.045'::jsonb, false);
  v_config := jsonb_set(v_config, '{worldBossRules,slotTiers,19,difficultyMultiplier}', '1.091'::jsonb, false);
  v_config := jsonb_set(v_config, '{worldBossRules,slotTiers,20,difficultyMultiplier}', '1.182'::jsonb, false);
  v_hash := encode(digest(v_config::text, 'sha256'), 'hex');

  insert into public.gacha_s2_balance_versions (
    version, config, config_hash, catalog_hash, active
  )
  select
    '2026.07.30-hell10-worldboss-retune-1',
    v_config,
    v_hash,
    catalog_hash,
    false
  from public.gacha_s2_balance_versions
  where active
  on conflict (version) do update
  set config = excluded.config,
      config_hash = excluded.config_hash,
      catalog_hash = excluded.catalog_hash,
      active = false;

  update public.gacha_s2_balance_versions
  set active = (version = '2026.07.30-hell10-worldboss-retune-1');
end;
$hell10_retune$;

-- 이미 전투가 시작된 회차의 피해량은 보존하고, 아직 시작하지 않았고 피해가 0인 회차만 맞춘다.
select public.gacha_s2_resync_world_boss_hp(now());

do $verify$
declare
  v_version text;
  v_config jsonb;
begin
  select version, config into v_version, v_config
  from public.gacha_s2_balance_versions
  where active;

  if v_version <> '2026.07.30-hell10-worldboss-retune-1' then
    raise exception 'Hell10 balance activation failed: %', coalesce(v_version, 'none');
  end if;
  if (v_config->'regions'->10->>'bossHp')::bigint <> 48000000
    or (v_config->'regions'->10->>'bossAttack')::bigint <> 50000 then
    raise exception 'Hell10 region balance update failed';
  end if;
  if v_config->'stages'->109->>'id' <> '11-10'
    or (v_config->'stages'->109->>'enemyHp')::bigint <> 48000000
    or (v_config->'stages'->109->>'enemyAttack')::bigint <> 50000
    or (v_config->'stages'->109->>'duration')::integer <> 78 then
    raise exception 'Hell10 stage balance update failed';
  end if;
  if (v_config->'archetypes'->'boss'->>'bossDamage')::numeric <> 2.0
    or (v_config->'archetypes'->'area'->>'area')::numeric <> 1.5 then
    raise exception 'Trait coefficients regressed';
  end if;
  if (v_config->'worldBossRules'->>'maxHp')::bigint <> 11000000000
    or (v_config->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint <> 11000000000
    or (v_config->'worldBossRules'->'slotTiers'->'18'->>'maxHp')::bigint <> 11500000000
    or (v_config->'worldBossRules'->'slotTiers'->'19'->>'maxHp')::bigint <> 12000000000
    or (v_config->'worldBossRules'->'slotTiers'->'20'->>'maxHp')::bigint <> 13000000000 then
    raise exception 'World boss HP update failed';
  end if;
  if (v_config->'worldBossRules'->'slotTiers'->'18'->>'difficultyMultiplier')::numeric <> 1.045
    or (v_config->'worldBossRules'->'slotTiers'->'19'->>'difficultyMultiplier')::numeric <> 1.091
    or (v_config->'worldBossRules'->'slotTiers'->'20'->>'difficultyMultiplier')::numeric <> 1.182 then
    raise exception 'World boss difficulty multiplier update failed';
  end if;
end;
$verify$;

do $verify_pending_worldboss$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from public.gacha_s2_world_boss_events w
  join public.gacha_s2_balance_versions b on b.active
  where w.starts_at >= now()
    and w.player_damage = 0
    and w.max_hp is distinct from
        (b.config->'worldBossRules'->'slotTiers'->((right(w.event_id, 2))::integer)::text->>'maxHp')::bigint;

  if v_bad > 0 then
    raise exception 'pending world boss rounds still out of sync: %', v_bad;
  end if;
end;
$verify_pending_worldboss$;

commit;
