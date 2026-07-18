import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { PACKS, STAGES } from '../src/renewal/config.js';
import { computeCardPower, computeCardStats, computeFormationPower, getFormationAmplifier, getRaceSynergy, simulateBattle } from '../src/renewal/battle.js';

const cards = JSON.parse(await fs.readFile(new URL('../data/renewal-demo-cards.json', import.meta.url), 'utf8'));
const formation = cards.slice(0, 5);

assert.equal(cards.length, 20, 'demo card pool must contain 20 cards');
assert.equal(new Set(cards.map((card) => card.id)).size, 20, 'demo card ids must be unique');
assert.equal(STAGES.length, 50, 'expanded adventure must contain 50 stages');

Object.entries(PACKS).forEach(([packId, pack]) => {
  const total = Object.values(pack.rates).reduce((sum, rate) => sum + rate, 0);
  assert.ok(Math.abs(total - 100) < 0.00001, `${packId} rates must sum to 100`);
});

cards.forEach((card) => {
  const stats = computeCardStats(card);
  assert.ok(stats && stats.atk > 0 && stats.hp > 0 && stats.def > 0, `${card.id} must have valid battle stats`);
});

assert.ok(computeFormationPower(formation) > 0, 'formation power must be positive');
const first = simulateBattle(formation, STAGES[0]);
const second = simulateBattle(formation, STAGES[0]);
assert.deepEqual(first, second, 'same formation and stage must produce deterministic results');
assert.ok(first.events.length > 0, 'battle must produce playback events');
assert.equal(first.victory, true, 'default formation should clear stage 1');

const raceDeck = (sameRaceCount) => cards.slice(0, 5).map((card, index) => ({
  ...card,
  race: index < sameRaceCount ? 'Z' : index === 4 ? 'P' : 'T',
}));
assert.equal(getRaceSynergy(raceDeck(3)).atk, 1.05);
assert.equal(getRaceSynergy(raceDeck(4)).atk, 1.05, 'four matching cards must retain the three-card synergy');
assert.equal(getRaceSynergy(raceDeck(5)).atk, 1.12);

const roleCard = (archetype) => ({ id: `role-${archetype}`, rarity: 'SSS', enhancement: 0, archetype, race: 'Z' });
assert.ok(computeCardPower(roleCard('combo')) > computeCardPower(roleCard('sustain')), 'displayed power must reflect combat throughput instead of raw HP alone');
assert.equal(getFormationAmplifier([roleCard('amplify'), roleCard('quick')]), 1.04);

const areaDeck = Array.from({ length: 5 }, (_, index) => ({ ...roleCard('area'), id: `area-${index}` }));
const target = { id: 'area-target', enemyHp: 999_999_999, enemyAttack: 0, duration: 10 };
const areaNormal = simulateBattle(areaDeck, { ...target, boss: false });
const areaBoss = simulateBattle(areaDeck, { ...target, boss: true });
const totalDamage = (result) => result.damageByCard.reduce((sum, entry) => sum + entry.damage, 0);
assert.ok(totalDamage(areaNormal) > totalDamage(areaBoss), 'area bonus must apply to normal waves only');

console.log(`renewal battle tests passed: ${cards.length} cards, ${STAGES.length} stages, ${first.events.length} events`);
