import assert from 'node:assert/strict';
import { BONUS_DROP_RULES } from '../src/renewal/config.js';
import {
  adventureBonusDropRule,
  grantBonusDrop,
  rollAdventureBonusDrop,
  rollWorldBossBonusDrop,
} from '../src/renewal/bonus-loot.js';

function sequenceRandom(values) {
  let index = 0;
  return () => values[Math.min(index++, values.length - 1)];
}

const sum = (weights) => Object.values(weights).reduce((total, weight) => total + weight, 0);
assert.equal(sum(BONUS_DROP_RULES.itemWeights), 100);
assert.equal(sum(BONUS_DROP_RULES.packWeights), 100);
assert.equal(adventureBonusDropRule(0), null);
assert.equal(adventureBonusDropRule(9).dropRate, 0.18);
assert.equal(adventureBonusDropRule(10).dropRate, 0.24);
assert.equal(adventureBonusDropRule(50).dropRate, 0.5);

assert.equal(rollAdventureBonusDrop(50, sequenceRandom([0.5])), null, 'roll at the drop-rate boundary fails');
const adventureItem = rollAdventureBonusDrop(1, sequenceRandom([0, 0.99, 0]));
assert.deepEqual(adventureItem, {
  itemId: 'energySmall', name: '전술 배터리 S', category: '행동력', isPack: false,
});
const adventurePack = rollAdventureBonusDrop(50, sequenceRandom([0, 0, 0.999999]));
assert.equal(adventurePack.itemId, 'premiumTicket');
assert.equal(adventurePack.isPack, true);

assert.equal(rollWorldBossBonusDrop(false, sequenceRandom([0.35])), null, 'failed raid drop rate is 35%');
const failedRaidItem = rollWorldBossBonusDrop(false, sequenceRandom([0, 0.99, 0.5]));
assert.equal(failedRaidItem.isPack, false);
const clearedRaidPack = rollWorldBossBonusDrop(true, sequenceRandom([0, 0, 0]));
assert.equal(clearedRaidPack.itemId, 'generalTicket');
assert.equal(clearedRaidPack.isPack, true);

const granted = grantBonusDrop({ energySmall: 2, premiumTicket: 0 }, adventurePack);
assert.equal(granted.premiumTicket, 1);
assert.equal(granted.energySmall, 2);

assert.equal(BONUS_DROP_RULES.adventureTiers.at(-1).dropRate * BONUS_DROP_RULES.adventureTiers.at(-1).packShare, 0.15);
assert.equal(BONUS_DROP_RULES.worldBoss.cleared.dropRate * BONUS_DROP_RULES.worldBoss.cleared.packShare, 0.15);

console.log('renewal bonus loot tests passed: adventure tiers, raid outcomes, items, card-pack tickets');
