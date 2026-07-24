-- 월드보스 서버 자동딜(서버DPS) 완전 폐지. serverDamagePerSecond를 전 슬롯 0으로 설정해
-- (기존 attackWorldBoss RPC 로직은 그대로 두고 값만 0으로 무력화) 처치 여부가 순수
-- 참가자 합산딜 vs maxHp 비교로만 갈리게 한다. maxHp는 지정값으로 재설정:
-- 17시 40억 / 18시 45억 / 19시 60억 / 20시 65억.
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
$$;
