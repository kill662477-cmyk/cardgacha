import assert from 'node:assert/strict';
import {
  applySumSelection,
  evaluateSumSelection,
  hasValidSumMove,
  reshuffleSumTiles,
} from '../src/renewal/minigames.js';

const COLS = 17;
const ROWS = 10;

function boardToTiles(values) {
  return values.map((value, index) => ({
    index, row: Math.floor(index / COLS), column: index % COLS, value, active: true,
  }));
}

// First rectangle (row-major) whose active tiles sum to exactly 10 -> a player drag.
function findFirstMove(tiles) {
  for (let r1 = 0; r1 < ROWS; r1 += 1) {
    for (let r2 = r1; r2 < ROWS; r2 += 1) {
      for (let c1 = 0; c1 < COLS; c1 += 1) {
        for (let c2 = c1; c2 < COLS; c2 += 1) {
          const evaluation = evaluateSumSelection(
            tiles, COLS, { row: r1, column: c1 }, { row: r2, column: c2 },
          );
          if (evaluation.valid) return { start: r1 * COLS + c1, end: r2 * COLS + c2 };
        }
      }
    }
  }
  return null;
}

function tilesFrom(values, active) {
  return values.map((value, index) => ({
    index, row: Math.floor(index / COLS), column: index % COLS,
    value, active: active ? active[index] : true,
  }));
}

// Live play (what the client produces): greedily clear, reshuffle on deadlock, log drags.
function playSession(values, active) {
  let tiles = tilesFrom(values, active);
  const log = [];
  let score = 0;
  let atMs = 0;
  let reshuffles = 0;
  if (!hasValidSumMove(tiles, COLS, ROWS)) {
    const next = reshuffleSumTiles(tiles, COLS, ROWS);
    if (next) { tiles = next; reshuffles += 1; }
  }
  for (let guard = 0; guard < 400; guard += 1) {
    const move = findFirstMove(tiles);
    if (!move) break;
    const evaluation = evaluateSumSelection(
      tiles, COLS,
      { row: Math.floor(move.start / COLS), column: move.start % COLS },
      { row: Math.floor(move.end / COLS), column: move.end % COLS },
    );
    log.push({ start: move.start, end: move.end, atMs: atMs += 1 });
    tiles = applySumSelection(tiles, evaluation);
    score += evaluation.count;
    if (tiles.every((tile) => !tile.active)) return { log, score, remaining: 0, reshuffles };
    if (!hasValidSumMove(tiles, COLS, ROWS)) {
      const next = reshuffleSumTiles(tiles, COLS, ROWS);
      if (!next) break;
      tiles = next;
      reshuffles += 1;
    }
  }
  return { log, score, remaining: tiles.filter((tile) => tile.active).length, reshuffles };
}

// Server-style replay of the log (mirrors gacha_s2_verify_sum_ten_log): reconstruct
// board, run the same initial + post-clear reshuffle guards, sum against live values.
function serverReplay(values, log, active) {
  let tiles = tilesFrom(values, active);
  let score = 0;
  let remaining = 170;
  const reguard = () => {
    if (remaining > 0 && !hasValidSumMove(tiles, COLS, ROWS)) {
      const next = reshuffleSumTiles(tiles, COLS, ROWS);
      if (next) tiles = next;
    }
  };
  reguard();
  for (const action of log) {
    const evaluation = evaluateSumSelection(
      tiles, COLS,
      { row: Math.floor(action.start / COLS), column: action.start % COLS },
      { row: Math.floor(action.end / COLS), column: action.end % COLS },
    );
    if (evaluation.valid) {
      tiles = applySumSelection(tiles, evaluation);
      score += evaluation.count;
      remaining -= evaluation.count;
      reguard();
    }
  }
  return { score, remaining, completed: remaining === 0 };
}

// mulberry32 for reproducible pseudo-random boards.
function rng(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

let reshuffledRuns = 0;
for (let seed = 1; seed <= 400; seed += 1) {
  const random = rng(seed);
  const values = Array.from({ length: 170 }, () => 1 + Math.floor(random() * 9));
  const played = playSession(values);
  const replayed = serverReplay(values, played.log);
  assert.equal(replayed.score, played.score, `seed ${seed}: replay score must equal live score`);
  assert.equal(replayed.remaining, played.remaining, `seed ${seed}: remaining must match`);
  assert.ok(played.score >= 0 && played.score <= 170, `seed ${seed}: score in tile bounds`);
  if (played.reshuffles > 0) reshuffledRuns += 1;
}

// Crafted deadlock boards: only a few tiles active, current layout has no sum-10 but a
// reshuffle arrangement does -> both live-play and server-replay must reshuffle and agree.
function craft(cells) {
  const values = new Array(170).fill(0);
  const active = new Array(170).fill(false);
  for (const [index, value] of cells) { values[index] = value; active[index] = true; }
  return { values, active };
}
// row0 cols0..3 = [6,9,4,9]: no rectangle sums 10, but ascending [4,6,9,9] gives 4+6=10.
const rescue = craft([[0, 6], [1, 9], [2, 4], [3, 9]]);
const rescuePlay = playSession(rescue.values, rescue.active);
const rescueReplay = serverReplay(rescue.values, rescuePlay.log, rescue.active);
// (Partial-active crafted boards break the always-170-active invariant that the
// server's remaining counter assumes, so only score -- the reward input -- is compared.)
assert.ok(rescuePlay.reshuffles > 0, 'crafted board must trigger a reshuffle');
assert.equal(rescueReplay.score, rescuePlay.score, 'reshuffle: replay score matches live');
assert.equal(rescuePlay.score, 2, 'crafted rescue clears the 4+6 pair for 2 points');
reshuffledRuns += 1;

// Unrescuable multiset {9,9,2}: no arrangement sums 10 -> reshuffle returns null, game ends.
const dead = craft([[0, 9], [1, 9], [2, 2]]);
const deadPlay = playSession(dead.values, dead.active);
const deadReplay = serverReplay(dead.values, deadPlay.log, dead.active);
assert.equal(deadPlay.score, 0, 'unrescuable board scores nothing');
assert.equal(deadReplay.score, 0, 'unrescuable replay scores nothing');

assert.ok(reshuffledRuns > 0, 'expected some runs to reach a deadlock and reshuffle');

console.log('sumTen reshuffle tests passed: live-play == server-replay, reshuffle branch covered');
