-- 광역 특성 일반 웨이브 피해 계수 1.18 -> 1.5.
-- 신규 밸런스 버전으로 분리해 진행 중인 기존 모험 런의 검증 기록은 보존한다.
begin;

do $area_trait$
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
    '"2026.07.30-area-trait-1.5"'::jsonb,
    true
  );
  v_config := jsonb_set(
    v_config,
    '{archetypes,area,area}',
    '1.5'::jsonb,
    false
  );
  v_hash := encode(digest(v_config::text, 'sha256'), 'hex');

  insert into public.gacha_s2_balance_versions (
    version, config, config_hash, catalog_hash, active
  )
  select
    '2026.07.30-area-trait-1.5',
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
  set active = (version = '2026.07.30-area-trait-1.5');
end;
$area_trait$;

do $verify$
declare
  v_version text;
  v_config jsonb;
begin
  select version, config into v_version, v_config
  from public.gacha_s2_balance_versions
  where active;

  if v_version <> '2026.07.30-area-trait-1.5' then
    raise exception 'Area trait balance activation failed: %', coalesce(v_version, 'none');
  end if;
  if (v_config->'archetypes'->'area'->>'area')::numeric <> 1.5 then
    raise exception 'Area trait damage coefficient update failed';
  end if;
  if (v_config->'archetypes'->'boss'->>'bossDamage')::numeric <> 2.0 then
    raise exception 'Boss trait coefficient regressed';
  end if;
  if (v_config->'archetypes'->'area'->>'atk')::numeric <> 1.04
    or (v_config->'archetypes'->'area'->>'speed')::numeric <> 0.94 then
    raise exception 'Unexpected area archetype drift';
  end if;
end;
$verify$;

commit;
