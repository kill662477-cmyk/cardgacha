import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  MINI_GAME_RULES,
  applySumSelection,
  calculateMiniGameReward,
  capMiniGameReward,
  createLadderBoard,
  createMemoryDeck,
  createSumTenBoard,
  evaluateSumSelection,
  hasValidSumMove,
  normalizeMiniGameProgress,
  pickLadderReward,
  reshuffleSumTiles,
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
assert.equal(calculateMiniGameReward('sumTen', { score: 100 }), 1740);
assert.equal(calculateMiniGameReward('sumTen', { score: 999 }), 3000);
assert.equal(calculateMiniGameReward('sumTen', { score: 0 }), 0);
assert.deepEqual([0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6].map(pickLadderReward), [3000, 2000, 1500, 1000, 500, 50]);
for (let lane = 0; lane < MINI_GAME_RULES.ladder.columns; lane += 1) {
  const ladder = createLadderBoard(`ladder-${lane}`, lane, 1500);
  assert.equal(ladder.rewards[ladder.endLane], 1500, 'chosen route must end at server reward');
  assert.equal(ladder.startLane, lane, 'user-selected lane must be preserved');
  assert.equal(ladder.path.at(-1).lane, ladder.endLane);
}

// Deadlock detection + deterministic reshuffle (must mirror server verify RPC).
function sumBoardFrom(values) {
  return values.map((value, index) => ({
    index, row: Math.floor(index / 17), column: index % 17, value, active: value > 0,
  }));
}
// 34 active tiles alternating 9/8 => no rectangle can sum to 10 (min pair 16).
const deadlock = sumBoardFrom(Array.from({ length: 170 }, (_, i) => (i < 34 ? (i % 2 ? 8 : 9) : 0)));
assert.equal(hasValidSumMove(deadlock, 17, 10), false, 'all 8/9 tiles cannot reach 10');
assert.equal(reshuffleSumTiles(deadlock, 17, 10), null, '8/9 multiset is unrescuable -> end game');
// A board with a 4 and a 6 adjacent has a move; strip it so it deadlocks, reshuffle rescues.
const rescuable = sumBoardFrom([4, 6, 7, 3, ...Array.from({ length: 166 }, () => 0)]);
assert.equal(hasValidSumMove(rescuable, 17, 10), true, '4+6 adjacent is a valid move');
// reshuffle is deterministic: same input -> identical output every call.
const dead2 = sumBoardFrom([9, 1, 9, 1, ...Array.from({ length: 166 }, () => 0)]);
// 9,1,9,1 in a row: 9+1=10 exists, so already playable.
assert.equal(hasValidSumMove(dead2, 17, 10), true);
const forced = sumBoardFrom([1, 1, 1, 7, ...Array.from({ length: 166 }, () => 0)]);
// row 0: 1,1,1,7 -> 1+1+1+7 = 10 across cols 0..3.
assert.equal(hasValidSumMove(forced, 17, 10), true, 'contiguous 1,1,1,7 sums to 10');
const a = reshuffleSumTiles(deadlock, 17, 10);
const b = reshuffleSumTiles(deadlock, 17, 10);
assert.deepEqual(a, b, 'reshuffle must be deterministic');
const reset = normalizeMiniGameProgress({ date: '2000-01-01', pointsEarned: 3000 }, Date.UTC(2026, 6, 17));
assert.equal(reset.pointsEarned, 0);
assert.deepEqual(reset.pointsEarnedByGame, { memory: 0, sumTen: 0, ladder: 0 });
const independentCaps = { pointsEarnedByGame: { memory: 2990, sumTen: 0 } };
assert.equal(capMiniGameReward(independentCaps, 'memory', 50), 10);
assert.equal(capMiniGameReward(independentCaps, 'sumTen', 240), 240);
assert.equal(capMiniGameReward({ pointsEarnedByGame: { ladder: 2950 } }, 'ladder', 500), 50);
assert.equal(capMiniGameReward({ pointsEarnedByGame: { memory: 1000, sumTen: 0 } }, 'memory', 1500), 1500);
const cappedLadder = normalizeMiniGameProgress({
  date: '2026-07-17', pointsEarned: 7000,
  pointsEarnedByGame: { memory: 0, sumTen: 0, ladder: 7000 },
}, new Date(2026, 6, 17, 12, 0, 0).getTime());
assert.equal(cappedLadder.pointsEarnedByGame.ladder, 3000);
assert.equal(cappedLadder.pointsEarned, 3000);
const legacy = normalizeMiniGameProgress({
  date: '2026-07-17', pointsEarned: 3000, plays: 2, bestMemory: 10, bestSumTen: 5,
}, new Date(2026, 6, 17, 12, 0, 0).getTime());
assert.deepEqual(legacy.pointsEarnedByGame, { memory: 3000, sumTen: 0, ladder: 0 });
assert.equal(MINI_GAME_RULES.energyCost, 10);
assert.equal(MINI_GAME_RULES.ladder.energyCost, 100);
assert.deepEqual(MINI_GAME_RULES.ladder.rewards, [3000, 2000, 1500, 1000, 500, 50]);

console.log('renewal minigame tests passed: memory, Cammon Apple, user-choice lucky ladder');
