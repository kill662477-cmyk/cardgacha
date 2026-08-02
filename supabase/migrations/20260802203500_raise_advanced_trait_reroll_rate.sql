-- 고급 작전 지원 보급팩의 랜덤특성변경권을 0.01%에서 0.03%로 상향한다.
-- 증가분 0.02%p는 비레어 빠른 전투 초기화권에서 차감해 총합과 다른 레어 확률을 유지한다.
begin;

do $balance$
declare
  v_config jsonb;
  v_items jsonb;
  v_total numeric;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active
  for update;

  if v_config is null then
    raise exception 'active balance config missing';
  end if;

  v_items := v_config->'advancedSupportPack'->'items';
  if (v_items->>'traitReroll')::numeric <> 0.01
    or (v_items->>'quickBattleReset')::numeric <> 3.99 then
    raise exception 'unexpected advanced support baseline: traitReroll %, quickBattleReset %',
      v_items->>'traitReroll', v_items->>'quickBattleReset';
  end if;

  v_items := v_items || jsonb_build_object(
    'traitReroll', 0.03,
    'quickBattleReset', 3.97
  );

  select sum(value::numeric) into v_total
  from jsonb_each_text(v_items);
  if v_total <> 100 then
    raise exception 'advanced support weights must total 100, got %', v_total;
  end if;

  v_config := jsonb_set(v_config, '{advancedSupportPack,items}', v_items, true);
  v_config := jsonb_set(v_config, '{advancedSupportPack,guaranteeRates}', v_items, true);

  if (v_config->'advancedSupportPack'->'items'->>'traitReroll')::numeric <> 0.03
    or (v_config->'advancedSupportPack'->'items'->>'quickBattleReset')::numeric <> 3.97
    or (v_config->'advancedSupportPack'->'items'->>'destructionGuard')::numeric <> 15
    or (v_config->'advancedSupportPack'->'items'->>'adventureRunReset')::numeric <> 0.5
    or v_config->'advancedSupportPack'->'guaranteeRates' <> v_items
    or not (v_config->'advancedSupportPack'->'rareItems' ? 'traitReroll')
    or (v_config->'advancedSupportPack'->>'tenGuarantee')::boolean <> false then
    raise exception 'advanced trait reroll rate update failed';
  end if;

  update public.gacha_s2_balance_versions
  set config = v_config,
      config_hash = encode(digest(v_config::text, 'sha256'), 'hex')
  where active;
end;
$balance$;

commit;
