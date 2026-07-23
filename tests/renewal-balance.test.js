import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { STAGES } from '../src/renewal/config.js';
import { computeCardPower, simulateBattle } from '../src/renewal/battle.js';
import { calculateCollectionBonuses } from '../src/renewal/collection.js';

const cards = JSON.parse(await fs.readFile(new URL('../data/renewal-demo-cards.json', import.meta.url), 'utf8'));
const allCards = JSON.parse(await fs.readFile(new URL('../data/renewal-cards.json', import.meta.url), 'utf8'));
const topDeck = cards.slice(0, 5).map((card) => ({ ...card, enhancement: 0 }));
const midDeck = cards.slice(5, 10).map((card) => ({ ...card, enhancement: 0 }));
const lowDeck = cards.slice(15, 20).map((card) => ({ ...card, enhancement: 0 }));
const maxedTopDeck = topDeck.map((card) => ({ ...card, enhancement: 9 }));
const maxedLowDeck = lowDeck.map((card) => ({ ...card, enhancement: 9 }));
const fullCollection = calculateCollectionBonuses(allCards, Object.fromEntries(allCards.map((card) => [card.id, true])));

assert.equal(simulateBattle(lowDeck, STAGES[1]).victory, true, 'unmaxed low deck should clear 1-2');
assert.equal(simulateBattle(lowDeck, STAGES[2]).victory, false, 'unmaxed low deck should stop at 1-3');
assert.equal(simulateBattle(midDeck, STAGES[9]).victory, true, 'mid deck should clear the first region');
assert.equal(simulateBattle(topDeck, STAGES[9]).victory, true, 'top deck should clear the first region');
assert.equal(simulateBattle(topDeck, STAGES[10]).victory, true, 'top deck may enter region 2');
STAGES.slice(0, 10).forEach((stage) => {
  assert.equal(simulateBattle(maxedLowDeck, stage).victory, true, `maxed low-rarity deck should clear ${stage.id}`);
});

for (let region = 0; region < 5; region += 1) {
  const stages = STAGES.slice(region * 10, region * 10 + 10);
  for (let index = 1; index < stages.length; index += 1) {
    if (!stages[index].boss) {
      assert.ok(stages[index].enemyHp / stages[index].duration > stages[index - 1].enemyHp / stages[index - 1].duration, `${stages[index].id} damage requirement must increase`);
    }
    const interval = stages[index].boss ? 1.15 : 1.45;
    const previousInterval = stages[index - 1].boss ? 1.15 : 1.45;
    assert.ok(stages[index].enemyAttack / interval > stages[index - 1].enemyAttack / previousInterval, `${stages[index].id} incoming pressure must increase`);
  }
}

assert.equal(simulateBattle(maxedTopDeck, STAGES[49], fullCollection).victory, true, 'maxed deck with full collection should clear the final boss');

// nolevel-1: S 9성(고강)과 SS 5~6성(중강) 덱은 계정 레벨 없이 완주 가능.
// 도감 보너스 없이도 완주해야 한다. D/E/F 9성 덱은 최종 보스에서 막힌다.
function rarityDeck(rarity, enhancement) {
  return allCards
    .filter((card) => card.rarity === rarity && card.archetype)
    .map((card) => ({ ...card, enhancement }))
    .sort((left, right) => computeCardPower(right) - computeCardPower(left))
    .slice(0, 5);
}
const cardOnlyBonuses = { attack: 0, hp: 0, defense: 0, bossDamage: 0, idle: 0 };
const normalStages = STAGES.filter((stage) => stage.mode === 'normal');
const clearsAll = (deck, bonuses) => normalStages.every((stage) => simulateBattle(deck, stage, bonuses).victory);
const stallsBeforeEnd = (deck, bonuses) => !simulateBattle(deck, STAGES[49], bonuses).victory;
const reaches = (deck, bonuses = cardOnlyBonuses) => {
  let cleared = 0;
  for (const stage of normalStages) {
    if (!simulateBattle(deck, stage, bonuses).victory) break;
    cleared = stage.globalNumber;
  }
  return cleared;
};

const fixedArchetypes = ['quick', 'heavy', 'combo', 'boss', 'sustain'];
const isolatedRarityDeck = (rarity, enhancement = 0) => fixedArchetypes.map((archetype, index) => ({
  id: `rarity-balance-${index}`,
  member: `등급검증${index}`,
  rarity,
  enhancement,
  archetype,
  race: 'Z',
}));
const zeroStarReach = ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'].map((rarity) => reaches(isolatedRarityDeck(rarity)));
assert.deepEqual(zeroStarReach, [3, 5, 8, 10, 11, 18, 20, 30, 40], 'zero-star rarity progression must reflect the SS/SSS rarity retune');

const combatRarities = ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'];
for (let rarityIndex = 1; rarityIndex < combatRarities.length; rarityIndex += 1) {
  for (const archetype of ['quick', 'heavy', 'combo', 'area', 'boss', 'amplify', 'weaken', 'sustain']) {
    const lower = allCards
      .filter((card) => card.rarity === combatRarities[rarityIndex - 1] && card.archetype === archetype)
      .map((card) => computeCardPower({ ...card, enhancement: 0 }));
    const higher = allCards
      .filter((card) => card.rarity === combatRarities[rarityIndex] && card.archetype === archetype)
      .map((card) => computeCardPower({ ...card, enhancement: 0 }));
    assert.ok(Math.min(...higher) > Math.max(...lower), `${combatRarities[rarityIndex]} ${archetype} must outrank the lower rarity at equal enhancement`);
  }
}

assert.equal(clearsAll(rarityDeck('SS', 9), fullCollection), true, 'SS 9성 deck with full collection must full-clear');
assert.equal(clearsAll(rarityDeck('S', 9), fullCollection), true, 'S 9성 deck with full collection can now full-clear after 5-10 nerf');
assert.equal(stallsBeforeEnd(isolatedRarityDeck('F', 9), cardOnlyBonuses), true, 'F 9성 deck must retain an endgame wall');
assert.equal(stallsBeforeEnd(isolatedRarityDeck('E', 9), cardOnlyBonuses), true, 'E 9성 deck must retain an endgame wall');
assert.equal(stallsBeforeEnd(isolatedRarityDeck('D', 9), cardOnlyBonuses), true, 'D 9성 deck must retain an endgame wall');
const lowRegion5Deck = [...rarityDeck('D', 9).slice(0, 2), ...rarityDeck('E', 9).slice(0, 2), ...rarityDeck('F', 9).slice(0, 1)];
assert.equal(stallsBeforeEnd(lowRegion5Deck, cardOnlyBonuses), true, 'low-rarity D/E/F 9성 deck must NOT full-clear (endgame wall)');

console.log('renewal balance tests passed: monotonic stages, low-rarity region 1, S9/SS5-6 full-clear, low-deck endgame wall');
