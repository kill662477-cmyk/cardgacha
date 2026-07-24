-- 월드보스 난이도 직전(1.3배) 대비 추가 2배 상향. maxHp·serverDamagePerSecond를
-- 슬롯 4종 + 공용값 전부 함께 2배 스케일해 처치 요구 딜(갭)이 정확히 2배 상승.
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
    '{worldBossRules,maxHp}', '13000000000'::jsonb, false),
    '{worldBossRules,serverDamagePerSecond}', '7193334'::jsonb, false),
    '{worldBossRules,slotTiers,17,maxHp}', '13000000000'::jsonb, false),
    '{worldBossRules,slotTiers,17,serverDamagePerSecond}', '7193334'::jsonb, false),
    '{worldBossRules,slotTiers,18,maxHp}', '19500000000'::jsonb, false),
    '{worldBossRules,slotTiers,18,serverDamagePerSecond}', '10790002'::jsonb, false),
    '{worldBossRules,slotTiers,19,maxHp}', '29250000000'::jsonb, false),
    '{worldBossRules,slotTiers,19,serverDamagePerSecond}', '16185002'::jsonb, false),
    '{worldBossRules,slotTiers,20,maxHp}', '43875000000'::jsonb, false),
    '{worldBossRules,slotTiers,20,serverDamagePerSecond}', '24277502'::jsonb, false)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint <> 13000000000 then
    raise exception 'worldboss slot17 hp update failed';
  end if;
  if (v_cfg->'worldBossRules'->'slotTiers'->'20'->>'serverDamagePerSecond')::bigint <> 24277502 then
    raise exception 'worldboss slot20 dps update failed';
  end if;
end;
$$;
