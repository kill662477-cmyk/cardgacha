-- 레어 보급지원 아이템 분해 환급을 일반 산식의 50%로 낮춘다.
-- 일반/고급 작전 지원 보급팩의 개별 확률은 유지하고 10회 레어 확정만 없앤다.
do $$
declare
  v_config jsonb;
  v_standard_items jsonb;
  v_advanced_items jsonb;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active;

  if v_config is null then
    raise exception 'active balance config missing';
  end if;

  v_standard_items := v_config->'supportPack'->'items';
  v_advanced_items := v_config->'advancedSupportPack'->'items';

  v_config := jsonb_set(v_config, '{supportItemDismantle,rareValueMultiplier}', '0.5'::jsonb, true);
  v_config := jsonb_set(
    v_config,
    '{supportItemDismantle,values}',
    coalesce(v_config->'supportItemDismantle'->'values', '{}'::jsonb)
      || jsonb_build_object(
        'destructionGuard', 30,
        'premiumTicket', 75,
        'adventureRunReset', 600,
        'quickBattleReset', 200
      ),
    true
  );

  v_config := jsonb_set(v_config, '{supportPack,tenGuarantee}', 'false'::jsonb, true);
  v_config := jsonb_set(v_config, '{supportPack,guaranteeRates}', v_standard_items, true);
  v_config := jsonb_set(v_config, '{advancedSupportPack,tenGuarantee}', 'false'::jsonb, true);
  v_config := jsonb_set(v_config, '{advancedSupportPack,guaranteeRates}', v_advanced_items, true);

  update public.gacha_s2_balance_versions
  set config = v_config
  where active;

  if (v_config->'supportItemDismantle'->>'rareValueMultiplier')::numeric <> 0.5
    or (v_config->'supportItemDismantle'->'values'->>'destructionGuard')::integer <> 30
    or (v_config->'supportItemDismantle'->'values'->>'premiumTicket')::integer <> 75
    or (v_config->'supportItemDismantle'->'values'->>'adventureRunReset')::integer <> 600
    or (v_config->'supportItemDismantle'->'values'->>'quickBattleReset')::integer <> 200
    or v_config->'supportItemDismantle'->'values' ? 'traitReroll'
    or (v_config->'supportPack'->>'tenGuarantee')::boolean <> false
    or v_config->'supportPack'->'guaranteeRates' <> v_standard_items
    or (v_config->'advancedSupportPack'->>'tenGuarantee')::boolean <> false
    or v_config->'advancedSupportPack'->'guaranteeRates' <> v_advanced_items then
    raise exception 'support item balance update failed';
  end if;
end;
$$;
