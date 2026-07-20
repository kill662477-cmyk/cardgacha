import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { REGIONS, STAGES } from '../src/renewal/config.js';
import { computeFormationPower, simulateBattle } from '../src/renewal/battle.js';
import { calculateCollectionBonuses } from '../src/renewal/collection.js';
import { applyLocalTestProfile } from '../src/renewal/local-test-profile.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cards = JSON.parse(fs.readFileSync(path.join(root, 'data', 'renewal-cards.json'), 'utf8'));
const combatRarities = ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'];
const combatArchetypes = ['quick', 'heavy', 'combo', 'area', 'boss', 'amplify', 'weaken', 'sustain'];
assert.equal(cards.length, 214);
assert.equal(new Set(cards.map((card) => card.id)).size, 214);
assert.equal(cards.filter((card) => card.rarity === 'EX').length, 8);
assert.ok(cards.filter((card) => card.rarity === 'EX').every((card) => card.member === '단체사진' && card.archetype === null));
const nonKimFurCards = cards.filter((card) => card.sourceRarity === 'FUR' && card.member !== '김윤환' && !card.group);
assert.equal(nonKimFurCards.length, 13);
assert.ok(nonKimFurCards.every((card) => card.rarity === 'SSS'));
assert.equal(cards.find((card) => card.id === 'vitaming-14').rarity, 'SSS');
assert.equal(cards.find((card) => card.id === 'imjoy-12').rarity, 'SSS');
assert.equal(cards.find((card) => card.id === 'meonjin-12').rarity, 'SSS');
const fixedSssIds = [
  'jidudu-1', 'kimyunhwan-2', 'kimyunhwan-4', 'tomato-6', 'nangni-8', 'jjiking-12', 'tomato-11', 'haetsal-12',
  'kimmincheol-7', 'sojuyang-13', 'chiri-14', 'namdeokseon-12', 'vitaming-14', 'imjoy-12', 'meonjin-12',
];
assert.deepEqual(cards.filter((card) => card.rarity === 'SSS').map((card) => card.id), fixedSssIds);
const deletedIds = ['juharang-5', 'sojuyang-5', 'chiri-10', 'nangni-12', 'sojuyang-11', 'sojuyang-12', 'jidudu-11', 'chiri-15'];
assert.ok(deletedIds.every((id) => !cards.some((card) => card.id === id)), 'deleted photos must be removed from the collection and pack pool');
const newRarities = {
  'kimyunhwan-7': 'SS', 'meonjin-13': 'SS', 'meonjin-14': 'S', 'sojuyang-14': 'SS', 'sojuyang-15': 'A',
  'juharang-12': 'SS', 'jidudu-13': 'SS', 'chiri-17': 'S', 'chiri-18': 'A', 'tomato-14': 'SS',
};
for (const [id, rarity] of Object.entries(newRarities)) assert.equal(cards.find((card) => card.id === id)?.rarity, rarity);
assert.deepEqual(Object.fromEntries(['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS'].map((rarity) => [
  rarity,
  cards.filter((card) => card.rarity === rarity).length,
])), { F: 24, E: 24, D: 24, C: 24, B: 24, A: 24, S: 24, SS: 23 });
assert.equal(cards.find((card) => card.id === 'group-1').rarity, 'EX');
assert.equal(cards.filter((card) => card.copies > 0).length, 20);
assert.ok(cards.filter((card) => card.rarity !== 'EX').every((card) => ['저그', '테란', '프로토스'].includes(card.race)));
assert.deepEqual(new Set(cards.filter((card) => card.rarity !== 'EX').map((card) => card.archetype)), new Set(['quick', 'heavy', 'combo', 'area', 'boss', 'amplify', 'weaken', 'sustain']));
combatRarities.forEach((rarity) => {
  const counts = combatArchetypes.map((archetype) => (
    cards.filter((card) => card.rarity === rarity && card.archetype === archetype).length
  ));
  assert.ok(counts.every((count) => count > 0), `${rarity} must contain every combat archetype`);
  assert.ok(Math.max(...counts) - Math.min(...counts) <= 1, `${rarity} archetypes must be evenly distributed`);
});
assert.ok(cards.every((card) => fs.existsSync(path.join(root, 'assets', 'cards', card.file))));

const localProfile = {
  revision: 0, nickname: 'before', points: 10, pendingPoints: 777,
  actionEnergy: 3, maxActionEnergy: 120, supportItems: { enhance5: 2, generalTicket: 1 },
  cardCopies: { [cards[0].id]: 3 }, collectionRecords: {},
};
assert.equal(applyLocalTestProfile(localProfile, cards, '127.0.0.1'), true);
assert.equal(localProfile.nickname, 'MSTZ');
assert.equal(localProfile.points, 1_000_000);
assert.equal(Object.hasOwn(localProfile, 'accountLevel'), false, 'local profile has no account level');
assert.equal(Object.hasOwn(localProfile, 'accountExp'), false, 'local profile has no account exp');
assert.equal(localProfile.pendingPoints, 0, 'no pending offline reward');
assert.equal(localProfile.actionEnergy, 120, 'energy refilled to max');
assert.ok(Object.values(localProfile.supportItems).every((count) => count === 0), 'no support items granted');
assert.equal(Object.keys(localProfile.collectionRecords).length, cards.length, 'local QA profile has full collection');
assert.ok(cards.every((card) => localProfile.collectionRecords[card.id] === true), 'every card registered in local collection');
assert.ok(cards.every((card) => localProfile.cardCopies[card.id] === 1), 'every card available for local QA');
const ongoingProfile = { revision: 5, points: 42 };
assert.equal(applyLocalTestProfile(ongoingProfile, cards, '127.0.0.1'), false, 'saved progress must not be reset');
assert.equal(ongoingProfile.points, 42);
const productionProfile = { nickname: 'live', points: 7, cardCopies: {}, collectionRecords: {} };
assert.equal(applyLocalTestProfile(productionProfile, cards, 'card-gacha.example.com'), false);
assert.equal(productionProfile.points, 7);
assert.equal(REGIONS.length, 5);
assert.equal(STAGES.length, 50);
assert.equal(STAGES.filter((stage) => stage.boss).length, 5);
assert.ok(STAGES.every((stage, index) => stage.globalNumber === index + 1));

const fullRecords = Object.fromEntries(cards.map((card) => [card.id, true]));
const collectionBonuses = calculateCollectionBonuses(cards, fullRecords);
const maxedCards = cards.filter((card) => card.rarity !== 'EX').map((card) => ({ ...card, enhancement: 9 }));
const raceDecks = [...new Set(maxedCards.map((card) => card.race))].map((race) => (
  maxedCards.filter((card) => card.race === race)
    .sort((left, right) => computeFormationPower([right, right, right, right, right], collectionBonuses)
      - computeFormationPower([left, left, left, left, left], collectionBonuses))
    .slice(0, 5)
));
const endgameDeck = raceDecks.sort((left, right) => (
  computeFormationPower(right, collectionBonuses) - computeFormationPower(left, collectionBonuses)
))[0];
STAGES.filter((stage) => stage.boss).forEach((boss) => {
  assert.equal(simulateBattle(endgameDeck, boss, collectionBonuses).victory, true, `${boss.id} must be reachable through card growth`);
});
const baseEndgameDeck = endgameDeck.map((card) => ({ ...card, enhancement: 0 }));
assert.equal(simulateBattle(baseEndgameDeck, STAGES[9], collectionBonuses).victory, true, 'high-rarity base deck clears region 1');
assert.equal(simulateBattle(baseEndgameDeck, STAGES[49]).victory, false, 'without a completed collection, enhancement remains required for final boss');

console.log('renewal content tests passed: 214 cards, 5 regions, 50 stages, fixed SSS, full F-SS regrade');
