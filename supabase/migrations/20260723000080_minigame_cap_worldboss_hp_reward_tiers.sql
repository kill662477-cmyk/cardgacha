-- balance-tune (runtime config): 서버 RPC들이 balance_versions.config JSON에서 읽으므로
-- 클라 config.js 변경과 별개로 활성 밸런스 config를 갱신해야 실제 반영된다.
--
-- 1) 미니게임 게임별 일일 포인트 상한 3,000 -> 10,000
--    (gacha_s2_finish_minigame / ladder 등이 config->miniGameRules->>dailyPointCapPerGame 참조)
-- 2) 월드보스 HP·서버DPS 각 슬롯 1.3배 상향(처치 요구 딜 갭이 정확히 1.3배 = 난이도 1.3배).
--    slotTiers.{17..20}.maxHp / serverDamagePerSecond + 기본 maxHp / serverDamagePerSecond.
-- 3) 월드보스 보상 티어 확장: 3,000만딜 20,000P / 4,000만딜 30,000P 차등 추가.
--
-- 기존 world_boss_events 행의 max_hp는 생성 시점 값이라 다음 회차부터 새 HP 적용된다.

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
  jsonb_set(
  jsonb_set(
    config,
    '{miniGameRules,dailyPointCapPerGame}', '10000'::jsonb, false),
    '{worldBossRules,maxHp}', '6500000000'::jsonb, false),
    '{worldBossRules,serverDamagePerSecond}', '3596667'::jsonb, false),
    '{worldBossRules,slotTiers,17,maxHp}', '6500000000'::jsonb, false),
    '{worldBossRules,slotTiers,17,serverDamagePerSecond}', '3596667'::jsonb, false),
    '{worldBossRules,slotTiers,18,maxHp}', '9750000000'::jsonb, false),
    '{worldBossRules,slotTiers,18,serverDamagePerSecond}', '5395001'::jsonb, false),
    '{worldBossRules,slotTiers,19,maxHp}', '14625000000'::jsonb, false),
    '{worldBossRules,slotTiers,19,serverDamagePerSecond}', '8092501'::jsonb, false),
    '{worldBossRules,slotTiers,20,maxHp}', '21937500000'::jsonb, false),
    '{worldBossRules,slotTiers,20,serverDamagePerSecond}', '12138751'::jsonb, false),
    '{worldBossRules,rewardTiers}', $tiers$[
      {"damage":1,"points":1000,"failurePoints":250,"label":"참여"},
      {"damage":2000000,"points":2000,"failurePoints":500,"label":"200만"},
      {"damage":5000000,"points":3500,"failurePoints":1000,"label":"500만"},
      {"damage":10000000,"points":5500,"failurePoints":2000,"label":"1,000만"},
      {"damage":15000000,"points":8000,"failurePoints":3000,"label":"1,500만"},
      {"damage":20000000,"points":10000,"failurePoints":5000,"label":"2,000만"},
      {"damage":30000000,"points":20000,"failurePoints":10000,"label":"3,000만"},
      {"damage":40000000,"points":30000,"failurePoints":15000,"label":"4,000만"}
    ]$tiers$::jsonb, false)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'miniGameRules'->>'dailyPointCapPerGame')::integer <> 10000 then
    raise exception 'minigame cap update failed';
  end if;
  if (v_cfg->'worldBossRules'->'slotTiers'->'17'->>'maxHp')::bigint <> 6500000000 then
    raise exception 'worldboss slot17 hp update failed';
  end if;
  if (v_cfg->'worldBossRules'->'slotTiers'->'20'->>'serverDamagePerSecond')::bigint <> 12138751 then
    raise exception 'worldboss slot20 dps update failed';
  end if;
  if jsonb_array_length(v_cfg->'worldBossRules'->'rewardTiers') <> 8 then
    raise exception 'reward tiers update failed';
  end if;
end;
$$;
