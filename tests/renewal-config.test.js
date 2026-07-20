import assert from 'node:assert/strict';
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
} from '../src/renewal/config.js';
import { MATERIAL_RULES } from '../src/renewal/enhancement.js';
import { MINI_GAME_RULES as EXPORTED_MINI_GAME_RULES } from '../src/renewal/minigames.js';
import { WORLD_BOSS_RULES as EXPORTED_WORLD_BOSS_RULES } from '../src/renewal/worldboss.js';

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
assert.equal(EXPORTED_MINI_GAME_RULES, MINI_GAME_RULES);
assert.equal(EXPORTED_WORLD_BOSS_RULES, WORLD_BOSS_RULES);
assert.equal(MATERIAL_RULES.SSS[1].count, 1);
assert.equal(ADVENTURE_RULES.maxRunsPerWindow, 3);
assert.equal(MINI_GAME_RULES.dailyPointCapPerGame, 3000);
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
assert.equal(WORLD_BOSS_RULES.raidDurationSeconds, 30 * 60);
assert.equal(Math.max(...WORLD_BOSS_RULES.rewardTiers.flatMap(({ points, failurePoints }) => [points, failurePoints])), 10000);
assert.equal(SOOP_RULES.pointsPerBalloon, 3);
assert.equal(EX_DISTRIBUTION_RULES.enabled, true);
assert.equal(EX_DISTRIBUTION_RULES.milestones.length, 8);
assert.equal(Object.values(PACKS).some((pack) => Object.hasOwn(pack.rates, 'EX')), false);
assert.deepEqual(EX_DISTRIBUTION_RULES.milestones.map(({ clearedStage }) => clearedStage), [5, 10, 15, 20, 25, 30, 40, 50]);
assert.equal(new Set(EX_DISTRIBUTION_RULES.milestones.map(({ cardId }) => cardId)).size, 8);
assert.strictEqual(BALANCE_VERSION, '2026.07.20-dismantle-1');
assert.equal(REGIONS[4].bossHp, 9_500_000, 'region 5 final boss uses card-only progression scale');
assert.equal(REGIONS[4].bossAttack, 21_000);
assert.equal(Object.hasOwn(BALANCE_GOVERNANCE, 'ACCOUNT_RULES'), false);
assert.ok(BALANCE_GOVERNANCE.locked.includes('ADVENTURE_RULES'));
assert.deepEqual(Object.keys(GROWTH_SIMULATION_PROFILES), ['low', 'mid', 'high']);

console.log(`renewal config tests passed: ${BALANCE_VERSION}, all probability tables total 100%`);
