import assert from 'node:assert/strict';
import { REWARD_RULES } from '../src/renewal/config.js';
import {
  applyCardExperience,
  calculateIdleReward,
  cardExpRequired,
  normalizeQuickBattle,
  recoverEnergy,
} from '../src/renewal/rewards.js';

const oneHour = calculateIdleReward(60 * 60 * 1000, 1);
const twoHours = calculateIdleReward(2 * 60 * 60 * 1000, 1);
const boostedTwoHours = calculateIdleReward(2 * 60 * 60 * 1000, 1, { cardExpBoostSeconds: 30 * 60 });
assert.ok(boostedTwoHours.cardExp > twoHours.cardExp, 'active EXP boost overlap must increase card EXP only for its duration');
const fullDay = calculateIdleReward(24 * 60 * 60 * 1000, 1);
const overCap = calculateIdleReward(72 * 60 * 60 * 1000, 1);
assert.ok(oneHour.cardExp > 0);
assert.equal(Object.hasOwn(oneHour, 'accountExp'), false);
assert.equal(Object.hasOwn(oneHour, 'materials'), false);
assert.equal(twoHours.cardExp, 5, 'opening stage should grant 5 card exp per two offline hours');
assert.deepEqual(overCap, fullDay, 'offline reward must stop at 24 hours');

const progress = applyCardExperience({}, [
  { id: 'card-a', enhancement: 0, exp: 95 },
  { id: 'card-b', enhancement: 2, exp: 0 },
], 20);
assert.equal(progress['card-a'].exp, cardExpRequired(0), 'card exp must cap at enhancement requirement');
assert.equal(progress['card-b'].exp, 20);

const now = Date.UTC(2026, 6, 16, 12, 0, 0);
const energy = recoverEnergy({ actionEnergy: 10, maxActionEnergy: 120, lastEnergyAt: now - 18 * 60 * 1000 }, now);
assert.equal(energy.energy, 13);
assert.equal(energy.recovered, 3);

assert.equal(normalizeQuickBattle({ date: '2000-01-01', count: 3 }, now).count, 0);
assert.equal(REWARD_RULES.quickBattleEnergy, 20);
assert.equal(REWARD_RULES.quickBattleHours, 2);

console.log('renewal reward tests passed: 24h cap, card EXP caps, energy recovery');
