import assert from 'node:assert/strict';
import fs from 'node:fs';
import { calculateCollectionBonuses, groupCollectionCardsByMember } from '../src/renewal/collection.js';
import { computeCardStats } from '../src/renewal/battle.js';
import { calculateIdleReward } from '../src/renewal/rewards.js';

const cards = JSON.parse(fs.readFileSync(new URL('../data/renewal-demo-cards.json', import.meta.url), 'utf8'));
const empty = calculateCollectionBonuses(cards, {});
assert.equal(empty.combatTotal, 0);
assert.equal(empty.idle, 0);

const records = Object.fromEntries(cards.map((card) => [card.id, true]));
const complete = calculateCollectionBonuses(cards, records);
assert.equal(complete.model.registered, cards.length);
assert.equal(complete.combatTotal, 0.7125);
assert.equal(complete.idle, 0.3);

const exCard = { ...cards[0], id: 'display-only-ex', rarity: 'EX' };
const withEx = calculateCollectionBonuses([...cards, exCard], { ...records, [exCard.id]: true });
assert.equal(withEx.model.total, cards.length, 'EX must be excluded from combat collection totals');
assert.equal(withEx.combatTotal, complete.combatTotal, 'EX must not add combat collection bonuses');

const baseStats = computeCardStats(cards[0]);
const boostedStats = computeCardStats(cards[0], complete);
assert.ok(boostedStats.atk > baseStats.atk);
assert.ok(boostedStats.hp > baseStats.hp);

const baseIdle = calculateIdleReward(60 * 60 * 1000, 1);
const boostedIdle = calculateIdleReward(60 * 60 * 1000, 1, { idleBonus: complete.idle });
assert.ok(boostedIdle.cardExp > baseIdle.cardExp);

const grouped = groupCollectionCardsByMember([
  { id: 'tomato-f', member: '토마토', rarity: 'F' },
  { id: 'yunhwan-s', member: '김윤환', rarity: 'S' },
  { id: 'tomato-sss', member: '토마토', rarity: 'SSS' },
  { id: 'group-ex', member: '단체사진', rarity: 'EX' },
  { id: 'yunhwan-a', member: '김윤환', rarity: 'A' },
]);
assert.deepEqual(grouped.map((group) => group.member), ['김윤환', '토마토', '단체사진']);
assert.deepEqual(grouped[0].cards.map((card) => card.id), ['yunhwan-s', 'yunhwan-a']);
assert.deepEqual(grouped[1].cards.map((card) => card.id), ['tomato-sss', 'tomato-f']);

console.log(`renewal collection tests passed: ${complete.model.registered}/${complete.model.total}, combat ${(complete.combatTotal * 100).toFixed(2)}%, idle ${(complete.idle * 100).toFixed(2)}%`);
