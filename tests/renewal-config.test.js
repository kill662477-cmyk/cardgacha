import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  ADVENTURE_RULES,
  BALANCE_GOVERNANCE,
  BALANCE_VERSION,
  EX_DISTRIBUTION_RULES,
  GROWTH_SIMULATION_PROFILES,
  MINI_GAME_RULES,
  PACKS,
  REGIONS,
  SOOP_RULES,
  SUPPORT_PACK,
  WORLD_BOSS_RULES,
  RARITIES,
} from '../src/renewal/config.js';
import { MATERIAL_RULES } from '../src/renewal/enhancement.js';
import { MINI_GAME_RULES as EXPORTED_MINI_GAME_RULES } from '../src/renewal/minigames.js';
import { WORLD_BOSS_RULES as EXPORTED_WORLD_BOSS_RULES } from '../src/renewal/worldboss.js';

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
assert.equal(SUPPORT_PACK.items.energySmall + SUPPORT_PACK.items.energyMedium + SUPPORT_PACK.items.energyLarge, 24);
assert.equal(SUPPORT_PACK.items.destructionGuard, 5);
assert.equal(SUPPORT_PACK.guaranteeRates.energyLarge, 7);
assert.equal(SUPPORT_PACK.guaranteeRates.destructionGuard, 6);
assert.equal(EXPORTED_MINI_GAME_RULES, MINI_GAME_RULES);
assert.equal(EXPORTED_WORLD_BOSS_RULES, WORLD_BOSS_RULES);
assert.equal(MATERIAL_RULES.SSS[1].count, 1);
assert.equal(ADVENTURE_RULES.maxRunsPerWindow, 3);
assert.equal(MINI_GAME_RULES.dailyPointCapPerGame, 3000);
assert.equal(MINI_GAME_RULES.ladder.energyCost, 100);
assert.deepEqual(MINI_GAME_RULES.ladder.rewards, [3000, 2000, 1500, 1000, 500, 50]);
assert.deepEqual(WORLD_BOSS_RULES.rewardTiers.map(({ damage, points, failurePoints }) => [damage, points, failurePoints]), [
  [1, 1000, 250],
  [2_000_000, 2000, 500],
  [5_000_000, 3500, 1000],
  [10_000_000, 5500, 2000],
  [15_000_000, 8000, 3000],
  [20_000_000, 10000, 5000],
]);
assert.equal(WORLD_BOSS_RULES.timeZone, 'Asia/Seoul');
assert.deepEqual(WORLD_BOSS_RULES.scheduleHours, [17, 18, 19, 20]);
assert.equal(WORLD_BOSS_RULES.attackEnergyCost, 10);
assert.deepEqual(Object.values(WORLD_BOSS_RULES.slotTiers).map(({ difficultyMultiplier, maxHp }) => [difficultyMultiplier, maxHp]), [
  [1, 5_000_000_000],
  [1.5, 7_500_000_000],
  [2.25, 11_250_000_000],
  [3.375, 16_875_000_000],
]);
assert.deepEqual(Object.values(WORLD_BOSS_RULES.slotTiers).map(({ clearDestructionGuardRate }) => clearDestructionGuardRate), [0.05, 0.10, 0.15, 0.20]);
assert.equal(WORLD_BOSS_RULES.raidDurationSeconds, 30 * 60);
assert.equal(Math.max(...WORLD_BOSS_RULES.rewardTiers.flatMap(({ points, failurePoints }) => [points, failurePoints])), 10000);
assert.equal(SOOP_RULES.pointsPerBalloon, 5);
assert.equal(EX_DISTRIBUTION_RULES.enabled, true);
assert.equal(EX_DISTRIBUTION_RULES.milestones.length, 8);
assert.equal(Object.values(PACKS).some((pack) => Object.hasOwn(pack.rates, 'EX')), false);
assert.deepEqual(EX_DISTRIBUTION_RULES.milestones.map(({ clearedStage }) => clearedStage), [5, 10, 15, 20, 25, 30, 40, 50]);
assert.equal(new Set(EX_DISTRIBUTION_RULES.milestones.map(({ cardId }) => cardId)).size, 8);
assert.strictEqual(BALANCE_VERSION, '2026.07.23-hard-adventure-1');
assert.deepEqual(ADVENTURE_RULES.modes.hard, {
  label: '하드 모험', startStage: 51, endStage: 100, stageCount: 50, unlockStage: 50,
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
assert.equal(REGIONS[4].bossHp, 8_250_000, 'region 5 final boss tuned to SS+7/collection-80% clear spec');
assert.equal(REGIONS[4].bossAttack, 21_000);
// balance-tune: 하드 최종 보스를 SSS 올 7강 + 풀도감 올클리어 스펙에 맞춰 하향.
assert.equal(REGIONS[9].bossHp, 18_900_000, 'hard final boss tuned to SSS+7/full-collection all-clear spec');
assert.equal(REGIONS.length, 10);
assert.ok(REGIONS.slice(5).every((region) => region.mode === 'hard'));
assert.equal(Object.hasOwn(BALANCE_GOVERNANCE, 'ACCOUNT_RULES'), false);
assert.ok(BALANCE_GOVERNANCE.locked.includes('ADVENTURE_RULES'));
assert.deepEqual(Object.keys(GROWTH_SIMULATION_PROFILES), ['low', 'mid', 'high']);

console.log(`renewal config tests passed: ${BALANCE_VERSION}, all probability tables total 100%`);
