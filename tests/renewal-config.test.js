import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  ADVENTURE_RULES,
  ARCHETYPES,
  BALANCE_GOVERNANCE,
  BALANCE_VERSION,
  EX_DISTRIBUTION_RULES,
  GROWTH_SIMULATION_PROFILES,
  MINI_GAME_RULES,
  PACKS,
  REGIONS,
  SOOP_RULES,
  SUPPORT_PACK,
  ADVANCED_SUPPORT_PACK,
  WORLD_BOSS_RULES,
  RARITIES,
} from '../src/renewal/config.js';
import { MATERIAL_RULES } from '../src/renewal/enhancement.js';
import { MINI_GAME_RULES as EXPORTED_MINI_GAME_RULES } from '../src/renewal/minigames.js';
import { WORLD_BOSS_RULES as EXPORTED_WORLD_BOSS_RULES } from '../src/renewal/worldboss.js';
import { WORLD_BOSS_RULES as SOURCE_WORLD_BOSS_RULES } from '../src/renewal/worldboss-rules.js';

const sssMultiplierMigration = (await readFile(
  new URL('../supabase/migrations/20260723000071_sss_multiplier_5.sql', import.meta.url),
  'utf8',
)).replace(/\s+/g, ' ');
const topRarityRetuneMigration = (await readFile(
  new URL('../supabase/migrations/20260723000072_ss_2_7_sss_4_8.sql', import.meta.url),
  'utf8',
)).replace(/\s+/g, ' ');
const sss46Migration = (await readFile(
  new URL('../supabase/migrations/20260723000073_sss_4_6.sql', import.meta.url),
  'utf8',
)).replace(/\s+/g, ' ');
const ss29Migration = (await readFile(
  new URL('../supabase/migrations/20260723000074_ss_2_9.sql', import.meta.url),
  'utf8',
)).replace(/\s+/g, ' ');
const appSource = await readFile(new URL('../src/renewal/app.js', import.meta.url), 'utf8');
const hell10RetuneMigration = await readFile(
  new URL('../supabase/migrations/20260730201000_hell10_boss_trait_retune.sql', import.meta.url),
  'utf8',
);
const adventureBalanceSyncMigration = await readFile(
  new URL('../supabase/migrations/20260730203000_sync_full_adventure_balance_config.sql', import.meta.url),
  'utf8',
);

const rateTotal = (rates) => Object.values(rates).reduce((sum, rate) => sum + rate, 0);
Object.values(PACKS).forEach((pack) => assert.ok(Math.abs(rateTotal(pack.rates) - 100) < 1e-9));
assert.deepEqual(Object.fromEntries(Object.entries(PACKS).map(([key, pack]) => [key, pack.rates.SSS])), {
  general: 0.006,
  elite: 0.012,
  premium: 0.05,
  race: 0.0006,
});
assert.equal(rateTotal(SUPPORT_PACK.items), 100);
assert.equal(rateTotal(SUPPORT_PACK.guaranteeRates), 100);
assert.equal(rateTotal(ADVANCED_SUPPORT_PACK.items), 100);
assert.equal(rateTotal(ADVANCED_SUPPORT_PACK.guaranteeRates), 100);
assert.equal(SUPPORT_PACK.items.energySmall + SUPPORT_PACK.items.energyMedium + SUPPORT_PACK.items.energyLarge, 24.21875);
assert.equal(SUPPORT_PACK.items.destructionGuard, 5);
assert.equal(SUPPORT_PACK.items.adventureRunReset, 0.03125);
assert.deepEqual(SUPPORT_PACK.rareItems, ['destructionGuard', 'premiumTicket', 'adventureRunReset', 'quickBattleReset', 'traitReroll']);
assert.deepEqual(ADVANCED_SUPPORT_PACK.rareItems, ['destructionGuard', 'adventureRunReset', 'traitReroll']);
assert.equal(ADVANCED_SUPPORT_PACK.price, 1500);
assert.equal(ADVANCED_SUPPORT_PACK.tenPrice, 15000);
assert.equal(ADVANCED_SUPPORT_PACK.items.destructionGuard, 15);
assert.equal(ADVANCED_SUPPORT_PACK.items.adventureRunReset, 0.5);
assert.equal(ADVANCED_SUPPORT_PACK.items.quickBattleReset, 3.97);
assert.equal(ADVANCED_SUPPORT_PACK.items.traitReroll, 0.03);
for (const pack of [SUPPORT_PACK, ADVANCED_SUPPORT_PACK]) {
  assert.equal(pack.tenGuarantee, false);
  assert.deepEqual(pack.guaranteeRates, pack.items, `${pack.name} 10회 확정 제거`);
  for (const [itemId, rate] of Object.entries(pack.items)) {
    assert.equal(pack.rareItems.includes(itemId), rate < 1 || itemId === 'destructionGuard', `${pack.name} ${itemId} rare label mismatch`);
  }
}
assert.equal(EXPORTED_MINI_GAME_RULES, MINI_GAME_RULES);
assert.equal(EXPORTED_WORLD_BOSS_RULES, WORLD_BOSS_RULES);
assert.equal(SOURCE_WORLD_BOSS_RULES, WORLD_BOSS_RULES);
assert.equal(MATERIAL_RULES.SSS[1].count, 1);
assert.equal(ADVENTURE_RULES.maxRunsPerWindow, 3);
assert.equal(MINI_GAME_RULES.dailyPointCapPerGame, 10000);
assert.equal(MINI_GAME_RULES.ladder.energyCost, 100);
assert.deepEqual(MINI_GAME_RULES.ladder.rewards, [3000, 2000, 1500, 1000, 500, 50]);
assert.deepEqual(WORLD_BOSS_RULES.rewardTiers.map(({ damage, points, failurePoints }) => [damage, points, failurePoints]), [
  [1, 1200, 300],
  [2_000_000, 2500, 600],
  [5_000_000, 4500, 1200],
  [10_000_000, 7000, 2000],
  [20_000_000, 12000, 4000],
  [30_000_000, 18000, 6000],
  [40_000_000, 24000, 9000],
  [50_000_000, 30000, 12000],
  [60_000_000, 40000, 15000],
  [70_000_000, 50000, 18000],
  [80_000_000, 60000, 21000],
  [90_000_000, 70000, 24000],
]);
// 티어 개수와 최대 지급액은 gacha_s2_world_boss_players 의 CHECK 제약 안에 있어야 한다.
// 과거 claimed_tier(<=5), reward_points(<=10000) 를 넘겨 보상 수령이 전부 실패한 사고가 있었다.
assert.ok(WORLD_BOSS_RULES.rewardTiers.length - 1 <= 15, 'claimed_tier 상한(15) 초과');
assert.ok(
  Math.max(...WORLD_BOSS_RULES.rewardTiers.map(({ points }) => points)) <= 100000,
  'reward_points 상한(100000) 초과',
);
// 딜 기준은 오름차순이어야 한다. SQL 이 ordinality 역순으로 최고 티어를 찾기 때문이다.
assert.deepEqual(
  WORLD_BOSS_RULES.rewardTiers.map(({ damage }) => damage),
  [...WORLD_BOSS_RULES.rewardTiers.map(({ damage }) => damage)].sort((a, b) => a - b),
);
assert.equal(WORLD_BOSS_RULES.timeZone, 'Asia/Seoul');
assert.deepEqual(WORLD_BOSS_RULES.scheduleHours, [17, 18, 19, 20]);
assert.equal(WORLD_BOSS_RULES.attackEnergyCost, 10);
assert.deepEqual(Object.values(WORLD_BOSS_RULES.slotTiers).map(({ difficultyMultiplier, maxHp }) => [difficultyMultiplier, maxHp]), [
  // 2026-08-11: 네 회차 모두 10억씩 상향(255/265/275/285 -> 265/275/285/295억).
  [1, 26_500_000_000],
  [1.038, 27_500_000_000],
  [1.075, 28_500_000_000],
  [1.113, 29_500_000_000],
]);
// difficultyMultiplier 는 표시 전용이라 17시 대비 HP 비율과 어긋나면 안내 문구가 거짓말이 된다.
for (const tier of Object.values(WORLD_BOSS_RULES.slotTiers)) {
  const ratio = tier.maxHp / WORLD_BOSS_RULES.slotTiers[17].maxHp;
  assert.ok(
    Math.abs(tier.difficultyMultiplier - ratio) < 0.005,
    `${tier.name} 난이도 배수(${tier.difficultyMultiplier})가 HP 비율(${ratio.toFixed(3)})과 다르다`,
  );
}
// 기본 maxHp 는 17시 슬롯과 같아야 한다(슬롯 조회 실패 시 폴백 값).
assert.equal(WORLD_BOSS_RULES.maxHp, WORLD_BOSS_RULES.slotTiers[17].maxHp);
// balance-tune: 서버 자동딜 폐지 -> 모든 슬롯 serverDamagePerSecond는 0.
assert.deepEqual(Object.values(WORLD_BOSS_RULES.slotTiers).map(({ serverDamagePerSecond }) => serverDamagePerSecond), [0, 0, 0, 0]);
assert.equal(WORLD_BOSS_RULES.serverDamagePerSecond, 0);
assert.deepEqual(Object.values(WORLD_BOSS_RULES.slotTiers).map(({ clearDestructionGuardRate }) => clearDestructionGuardRate), [0.05, 0.10, 0.15, 0.20]);
assert.equal(WORLD_BOSS_RULES.raidDurationSeconds, 30 * 60);
assert.equal(Math.max(...WORLD_BOSS_RULES.rewardTiers.flatMap(({ points, failurePoints }) => [points, failurePoints])), 70000);
assert.equal(SOOP_RULES.pointsPerBalloon, 100);
assert.equal(EX_DISTRIBUTION_RULES.enabled, true);
assert.equal(EX_DISTRIBUTION_RULES.milestones.length, 8);
assert.equal(Object.values(PACKS).some((pack) => Object.hasOwn(pack.rates, 'EX')), false);
assert.deepEqual(EX_DISTRIBUTION_RULES.milestones.map(({ clearedStage }) => clearedStage), [5, 10, 15, 20, 25, 30, 40, 50]);
assert.equal(new Set(EX_DISTRIBUTION_RULES.milestones.map(({ cardId }) => cardId)).size, 8);
assert.strictEqual(BALANCE_VERSION, '2026.07.30-hell10-worldboss-retune-2');
assert.equal(ARCHETYPES.boss.bossDamage, 2.0);
assert.equal(ARCHETYPES.area.area, 1.5);
assert.match(appSource, /\$\{ARCHETYPES\.combo\.multiHit\}배/, '연타 설명은 현재 설정값을 표시해야 한다');
assert.match(appSource, /\$\{ARCHETYPES\.area\.area\}배/, '광역 설명은 현재 설정값을 표시해야 한다');
assert.match(appSource, /\$\{ARCHETYPES\.boss\.bossDamage\}배/, '보스 설명은 현재 설정값을 표시해야 한다');
assert.doesNotMatch(
  appSource,
  /연타 피해 계수 1\.18배|광역 피해 계수 1\.22배|보스 피해 계수 1\.28배/,
  '과거 특성 계수 문구가 남으면 안 된다',
);
assert.match(hell10RetuneMigration, /\{regions,10,bossHp\}.*48000000/s);
assert.match(hell10RetuneMigration, /\{stages,109,enemyHp\}.*48000000/s);
assert.match(hell10RetuneMigration, /2026\.07\.30-hell10-worldboss-retune-1/);
assert.match(hell10RetuneMigration, /\{worldBossRules,slotTiers,20,maxHp\}.*13000000000/s);
assert.match(hell10RetuneMigration, /gacha_s2_resync_world_boss_hp\(now\(\)\)/);
assert.match(adventureBalanceSyncMigration, /jsonb_array_length\(v_config->'regions'\) is distinct from 11/);
assert.match(adventureBalanceSyncMigration, /jsonb_array_length\(v_config->'stages'\) is distinct from 110/);
assert.match(adventureBalanceSyncMigration, /2026\.07\.30-hell10-worldboss-retune-2/);
assert.deepEqual(ADVENTURE_RULES.modes.hard, {
  label: '하드 모험', startStage: 51, endStage: 100, stageCount: 50, unlockStage: 50,
});
assert.deepEqual(ADVENTURE_RULES.modes.hell, {
  label: 'HELL', startStage: 101, endStage: 110, stageCount: 10, unlockStage: 100,
});
assert.equal(ADVENTURE_RULES.hardRunReward.minPointsPerRun, 7000);
assert.equal(ADVENTURE_RULES.hardRunReward.maxPointsPerRun, 20000);
assert.equal(RARITIES.SS.multiplier, 2.9);
assert.equal(RARITIES.SSS.multiplier, 4.6);
assert.ok(
  RARITIES.SSS.multiplier * 1.44 > RARITIES.S.multiplier * 3,
  'SSS +3 must be stronger than S +9 at the same archetype and card variation',
);
assert.match(sssMultiplierMigration, /'\{rarities,SSS,multiplier\}', '5'::jsonb/);
assert.match(sssMultiplierMigration, /SSS \+3 must exceed S \+9/);
assert.match(topRarityRetuneMigration, /'\{rarities,SS,multiplier\}', '2\.7'::jsonb/);
assert.match(topRarityRetuneMigration, /'\{rarities,SSS,multiplier\}', '4\.8'::jsonb/);
assert.match(topRarityRetuneMigration, /SSS \+3 must exceed S \+9/);
assert.match(sss46Migration, /'\{rarities,SSS,multiplier\}', '4\.6'::jsonb/);
assert.match(sss46Migration, /v_ss_multiplier <> 2\.7 or v_sss_multiplier <> 4\.6/);
assert.match(ss29Migration, /'\{rarities,SS,multiplier\}', '2\.9'::jsonb/);
assert.match(ss29Migration, /v_ss_multiplier <> 2\.9 or v_sss_multiplier <> 4\.6/);
// balance-tune: 5-10 보스를 SS 7강 + 도감 80% 스펙으로 클리어 가능하게 하향.
assert.equal(REGIONS[4].bossHp, 7_500_000, 'region 5 final boss tuned to SS+7/collection-80% clear spec');
assert.equal(REGIONS[4].bossAttack, 16_000);
// balance-tune(2026-07-26): 특성 상향 이후 하드가 너무 쉬워져 기준선을 SSS 올 8강 + 풀도감으로
// 다시 잡았다. 이 스펙이 10-10 을 제한시간 95% · 파티 HP 39% 로 겨우 통과하고 SSS+7 은 35 스테이지에서 막힌다.
// HP 는 시간 압박, 공격력은 생존 압박 담당이라 지역별 배수를 따로 뒀다.
assert.equal(REGIONS[9].bossHp, 27_216_000, 'hard final boss tuned to SSS+8/full-collection all-clear spec');
assert.equal(REGIONS[9].bossAttack, 48_195);
assert.deepEqual(
  REGIONS.slice(5, 10).map((region) => [region.hpBase, region.attackBase]),
  [[8_862_500, 26_393], [10_803_200, 30_281], [12_922_800, 36_975], [15_150_400, 44_880], [17_985_600, 48_960]],
  'hard region stats must stay on the rebalanced curve',
);
assert.equal(REGIONS.length, 11);
assert.ok(REGIONS.slice(5, 10).every((region) => region.mode === 'hard'));
assert.equal(REGIONS[10].mode, 'hell');
assert.equal(REGIONS[10].bossHp, 48_000_000);
assert.equal(REGIONS[10].bossAttack, 50_000);
assert.equal(Object.hasOwn(BALANCE_GOVERNANCE, 'ACCOUNT_RULES'), false);
assert.ok(BALANCE_GOVERNANCE.locked.includes('ADVENTURE_RULES'));
assert.deepEqual(Object.keys(GROWTH_SIMULATION_PROFILES), ['low', 'mid', 'high']);

console.log(`renewal config tests passed: ${BALANCE_VERSION}, all probability tables total 100%`);
