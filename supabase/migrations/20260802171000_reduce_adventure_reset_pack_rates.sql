-- 모험 초기화권을 이용한 포인트 순환을 막기 위해 두 지원팩의 출현율을 낮춘다.
do $$
declare
  v_config jsonb;
  v_standard_items jsonb;
  v_advanced_items jsonb;
  v_total numeric;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active;

  if v_config is null then
    raise exception 'active balance config missing';
  end if;

  v_standard_items := v_config->'supportPack'->'items'
    || jsonb_build_object('energySmall', 14.21875, 'adventureRunReset', 0.03125);
  v_advanced_items := v_config->'advancedSupportPack'->'items'
    || jsonb_build_object('energyLarge', 14.5, 'adventureRunReset', 0.5);

  v_config := jsonb_set(v_config, '{supportPack,items}', v_standard_items, true);
  v_config := jsonb_set(v_config, '{supportPack,guaranteeRates}', v_standard_items, true);
  v_config := jsonb_set(v_config, '{advancedSupportPack,items}', v_advanced_items, true);
  v_config := jsonb_set(v_config, '{advancedSupportPack,guaranteeRates}', v_advanced_items, true);
  v_config := jsonb_set(
    v_config,
    '{advancedSupportPack,rareItems}',
    '["destructionGuard","adventureRunReset","traitReroll"]'::jsonb,
    true
  );
  v_config := jsonb_set(
    v_config,
    '{supportItemDismantle,baseValueCaps}',
    '{"adventureRunReset":1200}'::jsonb,
    true
  );

  select sum(value::numeric) into v_total from jsonb_each_text(v_standard_items);
  if v_total <> 100 then raise exception 'standard support weights must total 100, got %', v_total; end if;
  select sum(value::numeric) into v_total from jsonb_each_text(v_advanced_items);
  if v_total <> 100 then raise exception 'advanced support weights must total 100, got %', v_total; end if;

  if (v_standard_items->>'adventureRunReset')::numeric <> 0.03125
    or (v_standard_items->>'energySmall')::numeric <> 14.21875
    or (v_advanced_items->>'adventureRunReset')::numeric <> 0.5
    or (v_advanced_items->>'energyLarge')::numeric <> 14.5
    or v_config->'supportPack'->'guaranteeRates' <> v_standard_items
    or v_config->'advancedSupportPack'->'guaranteeRates' <> v_advanced_items
    or not (v_config->'advancedSupportPack'->'rareItems' ? 'adventureRunReset')
    or (v_config->'supportItemDismantle'->'values'->>'adventureRunReset')::integer <> 600 then
    raise exception 'adventure reset rate update failed';
  end if;

  update public.gacha_s2_balance_versions
  set config = v_config
  where active;
end;
$$;
