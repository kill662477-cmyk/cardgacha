update public.gacha_s2_balance_versions
set config =
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
  jsonb_set(
    config,
    '{worldBossRules,maxHp}', '4000000000'::jsonb, false),
    '{worldBossRules,serverDamagePerSecond}', '0'::jsonb, false),
    '{worldBossRules,slotTiers,17,maxHp}', '4000000000'::jsonb, false),
    '{worldBossRules,slotTiers,17,serverDamagePerSecond}', '0'::jsonb, false),
    '{worldBossRules,slotTiers,18,maxHp}', '4500000000'::jsonb, false),
    '{worldBossRules,slotTiers,18,serverDamagePerSecond}', '0'::jsonb, false),
    '{worldBossRules,slotTiers,19,maxHp}', '6000000000'::jsonb, false),
    '{worldBossRules,slotTiers,19,serverDamagePerSecond}', '0'::jsonb, false),
    '{worldBossRules,slotTiers,20,maxHp}', '6500000000'::jsonb, false),
    '{worldBossRules,slotTiers,20,serverDamagePerSecond}', '0'::jsonb, false)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint <> 4000000000 then
    raise exception 'worldboss slot17 hp update failed';
  end if;
  if (v_cfg->'worldBossRules'->'slotTiers'->'20'->>'serverDamagePerSecond')::bigint <> 0 then
    raise exception 'worldboss slot20 dps zero-out failed';
  end if;
end;
$$;;
