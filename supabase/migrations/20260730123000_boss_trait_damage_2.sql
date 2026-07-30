-- 보스 특성 전용 피해 계수 1.28 -> 2.0.
-- 신규 밸런스 버전으로 분리해 진행 중인 기존 모험 런의 검증 기록은 보존한다.
begin;

do $boss_trait$
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
    '"2026.07.30-boss-trait-2"'::jsonb,
    true
  );
  v_config := jsonb_set(
    v_config,
    '{archetypes,boss,bossDamage}',
    '2.0'::jsonb,
    false
  );
  v_hash := encode(digest(v_config::text, 'sha256'), 'hex');

  insert into public.gacha_s2_balance_versions (
    version, config, config_hash, catalog_hash, active
  )
  select
    '2026.07.30-boss-trait-2',
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
  set active = (version = '2026.07.30-boss-trait-2');
end;
$boss_trait$;

do $verify$
declare
  v_version text;
  v_config jsonb;
begin
  select version, config into v_version, v_config
  from public.gacha_s2_balance_versions
  where active;

  if v_version <> '2026.07.30-boss-trait-2' then
    raise exception 'Boss trait balance activation failed: %', coalesce(v_version, 'none');
  end if;
  if (v_config->'archetypes'->'boss'->>'bossDamage')::numeric <> 2.0 then
    raise exception 'Boss trait damage coefficient update failed';
  end if;
  if (v_config->'archetypes'->'boss'->>'atk')::numeric <> 1.08
    or (v_config->'archetypes'->'boss'->>'speed')::numeric <> 0.91 then
    raise exception 'Unexpected boss archetype drift';
  end if;
end;
$verify$;

commit;
