import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  MINI_GAME_RULES,
  applySumSelection,
  calculateMiniGameReward,
  capMiniGameReward,
  createMemoryDeck,
  createSumTenBoard,
  evaluateSumSelection,
  normalizeMiniGameProgress,
} from '../src/renewal/minigames.js';

const cards = JSON.parse(fs.readFileSync(new URL('../data/renewal-cards.json', import.meta.url), 'utf8'));
const memory = createMemoryDeck(cards, 'basic', 'fixed-seed');
const memoryAgain = createMemoryDeck(cards, 'basic', 'fixed-seed');
assert.deepEqual(memory, memoryAgain, 'same seed must reproduce memory deck');
assert.equal(memory.deck.length, 16);
assert.equal(new Set(memory.deck.map((card) => card.pairId)).size, 8);
assert.ok([...new Set(memory.deck.map((card) => card.pairId))].every((id) => memory.deck.filter((card) => card.pairId === id).length === 2));

const advanced = createMemoryDeck(cards, 'advanced', 'advanced-seed');
assert.equal(advanced.deck.length, 36);
assert.equal(advanced.columns, 6);

const sumBoard = createSumTenBoard('sum-seed');
assert.equal(sumBoard.tiles.length, 170);
assert.ok(sumBoard.tiles.every((tile) => tile.value >= 1 && tile.value <= 9));
const manualTiles = [
  { index: 0, row: 0, column: 0, value: 4, active: true },
  { index: 1, row: 0, column: 1, value: 6, active: true },
  { index: 2, row: 1, column: 0, value: 9, active: true },
  { index: 3, row: 1, column: 1, value: 9, active: true },
];
const valid = evaluateSumSelection(manualTiles, 2, { row: 0, column: 0 }, { row: 0, column: 1 });
assert.equal(valid.valid, true);
assert.equal(applySumSelection(manualTiles, valid).filter((tile) => tile.active).length, 2);
const invalid = evaluateSumSelection(manualTiles, 2, { row: 0, column: 0 }, { row: 1, column: 1 });
assert.equal(invalid.valid, false);

assert.equal(calculateMiniGameReward('memory', { completed: true, difficulty: 'basic', matches: 8, remainingSeconds: 30 }), 500);
assert.equal(calculateMiniGameReward('memory', { completed: true, difficulty: 'advanced', matches: 18, remainingSeconds: 1 }), 1500);
assert.equal(calculateMiniGameReward('memory', { completed: false }), 0);
assert.equal(calculateMiniGameReward('sumTen', { score: 100 }), 140);
assert.equal(calculateMiniGameReward('sumTen', { score: 999 }), 240);
const reset = normalizeMiniGameProgress({ date: '2000-01-01', pointsEarned: 3000 }, Date.UTC(2026, 6, 17));
assert.equal(reset.pointsEarned, 0);
assert.deepEqual(reset.pointsEarnedByGame, { memory: 0, sumTen: 0 });
const independentCaps = { pointsEarnedByGame: { memory: 2990, sumTen: 0 } };
assert.equal(capMiniGameReward(independentCaps, 'memory', 50), 10);
assert.equal(capMiniGameReward(independentCaps, 'sumTen', 240), 240);
assert.equal(capMiniGameReward({ pointsEarnedByGame: { memory: 1000, sumTen: 0 } }, 'memory', 1500), 1500);
const legacy = normalizeMiniGameProgress({
  date: '2026-07-17', pointsEarned: 3000, plays: 2, bestMemory: 10, bestSumTen: 5,
}, new Date(2026, 6, 17, 12, 0, 0).getTime());
assert.deepEqual(legacy.pointsEarnedByGame, { memory: 3000, sumTen: 0 });
assert.equal(MINI_GAME_RULES.energyCost, 10);

console.log('renewal minigame tests passed: 4x4 500P, 6x6 1500P, Cammon Apple, independent 3000P caps');
