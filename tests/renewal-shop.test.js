import assert from 'node:assert/strict';
import fs from 'node:fs';
import { ADVANCED_SUPPORT_PACK, PACKS, RACE_CHANGE_SELECTOR, SUPPORT_ITEMS, SUPPORT_PACK } from '../src/renewal/config.js';
import {
  addCardResults,
  cardExpPotionsNeeded,
  cardResultGridLayout,
  cardExpBoostSeconds,
  changeCardRace,
  drawCardPack,
  drawSupportPack,
  effectivePackRates,
  redeemCardSelector,
  rerollCardArchetype,
  useSupportItem,
  useCardExpPotion,
  useCardExpPotionBatch,
} from '../src/renewal/shop.js';

const cards = JSON.parse(fs.readFileSync(new URL('../data/renewal-demo-cards.json', import.meta.url), 'utf8'));
const advancedTraitRateMigration = fs.readFileSync(
  new URL('../supabase/migrations/20260802203500_raise_advanced_trait_reroll_rate.sql', import.meta.url),
  'utf8',
);
Object.values(PACKS).forEach((pack) => assert.ok(Math.abs(Object.values(pack.rates).reduce((sum, rate) => sum + rate, 0) - 100) < 1e-9));
assert.equal(Object.values(SUPPORT_PACK.items).reduce((sum, rate) => sum + rate, 0), 100);
assert.equal(Object.values(SUPPORT_PACK.guaranteeRates).reduce((sum, rate) => sum + rate, 0), 100);
assert.equal(SUPPORT_PACK.items.energySmall + SUPPORT_PACK.items.energyMedium + SUPPORT_PACK.items.energyLarge, 24.21875);
assert.equal(SUPPORT_PACK.items.destructionGuard, 5);
assert.equal(SUPPORT_PACK.items.adventureRunReset, 0.03125);
assert.equal(ADVANCED_SUPPORT_PACK.items.adventureRunReset, 0.5);
assert.equal(ADVANCED_SUPPORT_PACK.items.quickBattleReset, 3.97);
assert.equal(ADVANCED_SUPPORT_PACK.items.traitReroll, 0.03);
assert.equal(Object.values(ADVANCED_SUPPORT_PACK.items).reduce((sum, rate) => sum + rate, 0), 100);
assert.equal(Object.values(ADVANCED_SUPPORT_PACK.guaranteeRates).reduce((sum, rate) => sum + rate, 0), 100);
assert.equal(SUPPORT_ITEMS.ssCardSelector.cardSelectorRarity, 'SS');
assert.equal(SUPPORT_ITEMS.sssCardSelector.cardSelectorRarity, 'SSS');
assert.equal(Object.hasOwn(SUPPORT_PACK.items, 'ssCardSelector'), false, 'event selector must not drop from support pack');
assert.equal(Object.hasOwn(SUPPORT_PACK.items, 'sssCardSelector'), false, 'event selector must not drop from support pack');
assert.equal(SUPPORT_PACK.items.traitReroll, 0.001);
assert.equal(SUPPORT_PACK.rareItems.includes('traitReroll'), true, 'sub-1% item must be marked rare');
assert.equal(SUPPORT_PACK.tenGuarantee, false);
assert.equal(ADVANCED_SUPPORT_PACK.tenGuarantee, false);
assert.equal(SUPPORT_ITEMS.traitReroll.name, '랜덤특성변경권');
assert.equal(SUPPORT_ITEMS.raceChangeSelector.name, '종족선택 변경권');
assert.equal(RACE_CHANGE_SELECTOR.price, 20_000_000);
assert.equal(Object.hasOwn(SUPPORT_PACK.items, 'raceChangeSelector'), false, '종족 변경권은 확률형 보급팩에서 나오면 안 된다');
assert.equal(drawSupportPack(1, () => 0.9998, ADVANCED_SUPPORT_PACK)[0], 'traitReroll');
assert.equal(drawSupportPack(1, () => 0.9996, ADVANCED_SUPPORT_PACK)[0], 'quickBattleReset');
assert.match(advancedTraitRateMigration, /'traitReroll', 0\.03/);
assert.match(advancedTraitRateMigration, /'quickBattleReset', 3\.97/);
assert.match(advancedTraitRateMigration, /advanced support weights must total 100/);

const general = drawCardPack('general', cards, { random: () => 0 });
assert.equal(general.length, PACKS.general.count);
const terran = drawCardPack('race', cards, { race: '테란', random: () => 0.5 });
assert.ok(terran.every((id) => cards.find((card) => card.id === id).race === '테란'));
const terranRates = effectivePackRates('race', cards, '테란');
assert.ok(Math.abs(Object.values(terranRates).reduce((sum, rate) => sum + rate, 0) - 100) < 1e-9);
assert.ok(Object.keys(terranRates).every((rarity) => cards.some((card) => card.race === '테란' && card.rarity === rarity)));

const standardTen = drawSupportPack(10, () => 0);
assert.equal(standardTen.length, 10);
assert.equal(SUPPORT_PACK.rareItems.includes(standardTen[9]), false, 'standard tenth slot must not guarantee rare');
const advancedTen = drawSupportPack(10, () => 0, ADVANCED_SUPPORT_PACK);
assert.equal(advancedTen.length, 10);
assert.equal(ADVANCED_SUPPORT_PACK.rareItems.includes(advancedTen[9]), false, 'advanced tenth slot must not guarantee rare');

const cardState = addCardResults({}, {}, [cards[0].id, cards[0].id]);
assert.equal(cardState.copies[cards[0].id], 2);
assert.equal(cardState.collectionRecords[cards[0].id], true);

const ssCard = cards.find((card) => card.rarity === 'SS');
const sssCard = cards.find((card) => card.rarity === 'SSS');
const selectorState = {
  supportItems: { ssCardSelector: 1, sssCardSelector: 1 },
  cardCopies: {},
  collectionRecords: {},
};
const selectedSs = redeemCardSelector(selectorState, 'ssCardSelector', ssCard.id, cards);
assert.equal(selectedSs.used, true);
assert.equal(selectedSs.state.supportItems.ssCardSelector, 0);
assert.equal(selectedSs.state.cardCopies[ssCard.id], 1);
assert.equal(selectedSs.state.collectionRecords[ssCard.id], true);
assert.equal(redeemCardSelector(selectorState, 'ssCardSelector', sssCard.id, cards).used, false);

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

// Batch fill: consumes only as many potions as needed to reach the cap, even
// when more are owned (mirrors calling useCardExpPotion repeatedly).
const batchExact = useCardExpPotionBatch(
  { supportItems: { cardExpPotionLarge: 10 }, cardProgress: { target: { enhancement: 2, exp: 260 } } },
  'target', 300, 'cardExpPotionLarge',
);
assert.equal(batchExact.used, true);
assert.equal(batchExact.potionsUsed, 2, 'ceil((300-260)/20) = 2 potions, not all 10 owned');
assert.equal(batchExact.gained, 40);
assert.equal(batchExact.state.cardProgress.target.exp, 300);
assert.equal(batchExact.state.supportItems.cardExpPotionLarge, 8, 'unused potions remain in inventory');

// Batch fill: not enough owned to reach the cap -> uses everything owned, partial progress.
const batchPartial = useCardExpPotionBatch(
  { supportItems: { cardExpPotionLarge: 2 }, cardProgress: { target: { enhancement: 2, exp: 0 } } },
  'target', 300, 'cardExpPotionLarge',
);
assert.equal(batchPartial.used, true);
assert.equal(batchPartial.potionsUsed, 2);
assert.equal(batchPartial.gained, 40);
assert.equal(batchPartial.state.supportItems.cardExpPotionLarge, 0);

// Batch fill: none owned -> no-op.
const batchNone = useCardExpPotionBatch(
  { supportItems: { cardExpPotionLarge: 0 }, cardProgress: { target: { enhancement: 2, exp: 0 } } },
  'target', 300, 'cardExpPotionLarge',
);
assert.equal(batchNone.used, false);

// Batch fill: already at cap -> no-op even with potions owned.
const batchMaxed = useCardExpPotionBatch(
  { supportItems: { cardExpPotionLarge: 5 }, cardProgress: { target: { enhancement: 2, exp: 300 } } },
  'target', 300, 'cardExpPotionLarge',
);
assert.equal(batchMaxed.used, false);

assert.equal(
  cardExpPotionsNeeded(0, 300, 'cardExpPotionLarge'),
  15,
  '일괄 요청은 보유량이 아니라 실제 필요 수량을 보내야 한다',
);
const batchOverTenThousandOwned = useCardExpPotionBatch(
  { supportItems: { cardExpPotionLarge: 10_001 }, cardProgress: { target: { enhancement: 2, exp: 0 } } },
  'target', 300, 'cardExpPotionLarge',
);
assert.equal(batchOverTenThousandOwned.used, true);
assert.equal(batchOverTenThousandOwned.potionsUsed, 15);
assert.equal(batchOverTenThousandOwned.state.supportItems.cardExpPotionLarge, 9_986);

const rerollCard = cards.find((card) => card.rarity !== 'EX' && !card.group);
const rerollState = {
  supportItems: { traitReroll: 1 },
  cardCopies: { [rerollCard.id]: 1 },
  cardProgress: { [rerollCard.id]: { enhancement: 7, exp: 123 } },
};
const rerolled = rerollCardArchetype(rerollState, rerollCard.id, cards, () => 0);
assert.equal(rerolled.used, true);
assert.notEqual(rerolled.archetype, rerollCard.archetype, 'current trait must be excluded from random candidates');
assert.equal(rerolled.state.supportItems.traitReroll, 0);
assert.equal(rerolled.state.cardProgress[rerollCard.id].enhancement, 7);
assert.equal(rerolled.state.cardProgress[rerollCard.id].exp, 123);
assert.equal(rerolled.state.cardProgress[rerollCard.id].archetype, rerolled.archetype);

const raceChangeState = {
  supportItems: { raceChangeSelector: 1 },
  cardCopies: { [rerollCard.id]: 3 },
  cardProgress: { [rerollCard.id]: { enhancement: 7, exp: 123, archetype: rerolled.archetype } },
};
const nextRace = ['저그', '테란', '프로토스'].find((race) => race !== rerollCard.race);
const raceChanged = changeCardRace(raceChangeState, rerollCard.id, nextRace, cards);
assert.equal(raceChanged.used, true);
assert.equal(raceChanged.previousRace, rerollCard.race);
assert.equal(raceChanged.race, nextRace);
assert.equal(raceChanged.state.supportItems.raceChangeSelector, 0);
assert.equal(raceChanged.state.cardProgress[rerollCard.id].enhancement, 7);
assert.equal(raceChanged.state.cardProgress[rerollCard.id].archetype, rerolled.archetype);
assert.equal(raceChanged.state.cardProgress[rerollCard.id].race, nextRace);
assert.equal(changeCardRace(raceChangeState, rerollCard.id, rerollCard.race, cards).used, false, '현재 종족 재선택은 소비 없이 거절해야 한다');

console.log('renewal shop tests passed: card packs, support guarantee, selectors, random traits, consumables, resets, batch EXP potion fill');
