import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PACKS, SUPPORT_PACK } from '../src/renewal/config.js';
import {
  addCardResults,
  cardResultGridLayout,
  cardExpBoostSeconds,
  drawCardPack,
  drawSupportPack,
  effectivePackRates,
  useSupportItem,
  useCardExpPotion,
} from '../src/renewal/shop.js';

const cards = JSON.parse(fs.readFileSync(new URL('../data/renewal-demo-cards.json', import.meta.url), 'utf8'));
Object.values(PACKS).forEach((pack) => assert.ok(Math.abs(Object.values(pack.rates).reduce((sum, rate) => sum + rate, 0) - 100) < 1e-9));
assert.equal(Object.values(SUPPORT_PACK.items).reduce((sum, rate) => sum + rate, 0), 100);
assert.equal(Object.values(SUPPORT_PACK.guaranteeRates).reduce((sum, rate) => sum + rate, 0), 100);

const general = drawCardPack('general', cards, { random: () => 0 });
assert.equal(general.length, PACKS.general.count);
const terran = drawCardPack('race', cards, { race: '테란', random: () => 0.5 });
assert.ok(terran.every((id) => cards.find((card) => card.id === id).race === '테란'));
const terranRates = effectivePackRates('race', cards, '테란');
assert.ok(Math.abs(Object.values(terranRates).reduce((sum, rate) => sum + rate, 0) - 100) < 1e-9);
assert.ok(Object.keys(terranRates).every((rarity) => cards.some((card) => card.race === '테란' && card.rarity === rarity)));

const guaranteed = drawSupportPack(10, () => 0);
assert.equal(guaranteed.length, 10);
assert.ok(SUPPORT_PACK.rareItems.includes(guaranteed[9]), 'tenth slot must guarantee rare when first nine are common');

const cardState = addCardResults({}, {}, [cards[0].id, cards[0].id]);
assert.equal(cardState.copies[cards[0].id], 2);
assert.equal(cardState.collectionRecords[cards[0].id], true);

assert.deepEqual(cardResultGridLayout(3), { columns: 3, cardWidth: '150px', bulk: false });
assert.deepEqual(cardResultGridLayout(10), { columns: 5, cardWidth: '125px', bulk: false });
assert.deepEqual(cardResultGridLayout(40), { columns: 8, cardWidth: '1fr', bulk: true });

const baseState = {
  actionEnergy: 110, maxActionEnergy: 120, lastEnergyAt: 0,
  supportItems: { energyLarge: 1, exp30m: 2 }, activeBuffs: { cardExpStartAt: 0, cardExpEndAt: 0 },
};
const energy = useSupportItem(baseState, 'energyLarge', 1000);
assert.equal(energy.state.actionEnergy, 230);
const buff = useSupportItem(baseState, 'exp30m', 1000);
const extended = useSupportItem(buff.state, 'exp30m', 2000);
assert.equal(cardExpBoostSeconds(extended.state.activeBuffs, 1000, 3601000), 3600);

const resetNow = new Date(2026, 6, 17, 12, 0, 0).getTime();
const adventureResetState = {
  supportItems: { adventureRunReset: 1 }, activeBuffs: {},
  adventureRuns: { windowStartedAt: resetNow - 1000, count: 3 },
};
const adventureReset = useSupportItem(adventureResetState, 'adventureRunReset', resetNow);
assert.equal(adventureReset.used, true);
assert.deepEqual(adventureReset.state.adventureRuns, { windowStartedAt: 0, count: 0 });
assert.equal(adventureReset.state.supportItems.adventureRunReset, 0);
const unusedAdventureReset = useSupportItem({
  ...adventureResetState,
  adventureRuns: { windowStartedAt: 0, count: 0 },
}, 'adventureRunReset', resetNow);
assert.equal(unusedAdventureReset.used, false);
assert.equal(unusedAdventureReset.state.supportItems.adventureRunReset, 1);

const quickResetState = {
  supportItems: { quickBattleReset: 1 }, activeBuffs: {},
  quickBattle: { windowStartedAt: resetNow - 60 * 60 * 1000, count: 3 },
};
const quickReset = useSupportItem(quickResetState, 'quickBattleReset', resetNow);
assert.equal(quickReset.used, true);
assert.deepEqual(quickReset.state.quickBattle, { windowStartedAt: 0, count: 0 });
assert.equal(quickReset.state.supportItems.quickBattleReset, 0);
const unusedQuickReset = useSupportItem({
  ...quickResetState,
  quickBattle: { windowStartedAt: 0, count: 0 },
}, 'quickBattleReset', resetNow);
assert.equal(unusedQuickReset.used, false);
assert.equal(unusedQuickReset.state.supportItems.quickBattleReset, 1);

const potionState = { supportItems: { cardExpPotion: 1 }, cardProgress: { target: { enhancement: 2, exp: 250 } } };
const potion = useCardExpPotion(potionState, 'target', 300);
assert.equal(potion.used, true);
assert.equal(potion.gained, 50, 'potion EXP must stop at the current enhancement cap');
assert.equal(potion.state.cardProgress.target.exp, 300);
assert.equal(potion.state.supportItems.cardExpPotion, 0);

console.log('renewal shop tests passed: card packs, support guarantee, consumables, adventure and quick-battle resets');
