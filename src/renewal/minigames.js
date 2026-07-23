import { MINI_GAME_RULES } from './config.js';

export { MINI_GAME_RULES };

function hashSeed(value) {
  let hash = 2166136261;
  for (const character of String(value)) {
    hash ^= character.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function seededRandom(seed) {
  let state = hashSeed(seed);
  return () => {
    state += 0x6d2b79f5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffle(values, random) {
  const result = [...values];
  for (let index = result.length - 1; index > 0; index -= 1) {
    const target = Math.floor(random() * (index + 1));
    [result[index], result[target]] = [result[target], result[index]];
  }
  return result;
}

export function pickLadderReward(randomValue) {
  const rewards = MINI_GAME_RULES.ladder.rewards;
  const roll = Math.max(0, Math.min(0.999999999999, Number(randomValue) || 0));
  return rewards[Math.floor(roll * rewards.length)];
}

export function createLadderBoard(seed, startLane, winningReward) {
  const { columns, rungRows, rewards } = MINI_GAME_RULES.ladder;
  const lane = Math.max(0, Math.min(columns - 1, Math.floor(Number(startLane) || 0)));
  const reward = rewards.includes(winningReward) ? winningReward : rewards.at(-1);
  const random = seededRandom(seed);
  const rows = Array.from({ length: rungRows }, () => {
    const rungs = [];
    for (let edge = 0; edge < columns - 1; edge += 1) {
      if (rungs.includes(edge - 1)) continue;
      if (random() < 0.38) rungs.push(edge);
    }
    if (rungs.length === 0) rungs.push(Math.floor(random() * (columns - 1)));
    return rungs;
  });
  const path = [{ lane, row: -1 }];
  let currentLane = lane;
  rows.forEach((rungs, row) => {
    path.push({ lane: currentLane, row });
    if (rungs.includes(currentLane)) currentLane += 1;
    else if (rungs.includes(currentLane - 1)) currentLane -= 1;
    path.push({ lane: currentLane, row });
  });
  path.push({ lane: currentLane, row: rungRows });
  const otherRewards = shuffle(rewards.filter((value) => value !== reward), random);
  const bottomRewards = new Array(columns);
  bottomRewards[currentLane] = reward;
  let otherIndex = 0;
  for (let index = 0; index < columns; index += 1) {
    if (index !== currentLane) bottomRewards[index] = otherRewards[otherIndex++];
  }
  return { columns, rungRows, rows, startLane: lane, endLane: currentLane, path, rewards: bottomRewards };
}

export function createMemoryDeck(cards, difficulty = 'basic', seed = Date.now()) {
  const rules = MINI_GAME_RULES.memory[difficulty] ?? MINI_GAME_RULES.memory.basic;
  const candidates = cards.filter((card) => card.rarity !== 'EX');
  if (candidates.length < rules.pairs) throw new Error(`Memory game requires ${rules.pairs} unique cards.`);
  const random = seededRandom(seed);
  const selected = shuffle(candidates, random).slice(0, rules.pairs);
  const deck = shuffle(selected.flatMap((card) => [0, 1].map((copy) => ({
    key: `${card.id}:${copy}`,
    pairId: card.id,
    cardId: card.id,
    file: card.file,
    member: card.member,
    rarity: card.rarity,
  }))), random);
  return { difficulty, columns: rules.columns, pairs: rules.pairs, timeLimit: rules.timeLimit, deck };
}

export function createSumTenBoard(seed = Date.now()) {
  const { rows, columns, timeLimit } = MINI_GAME_RULES.sumTen;
  const random = seededRandom(seed);
  const tiles = Array.from({ length: rows * columns }, (_, index) => ({
    index,
    row: Math.floor(index / columns),
    column: index % columns,
    value: 1 + Math.floor(random() * 9),
    active: true,
  }));
  return { rows, columns, timeLimit, tiles };
}

export function evaluateSumSelection(tiles, columns, start, end) {
  const minRow = Math.min(start.row, end.row);
  const maxRow = Math.max(start.row, end.row);
  const minColumn = Math.min(start.column, end.column);
  const maxColumn = Math.max(start.column, end.column);
  const indices = tiles.filter((tile) => tile.active
    && tile.row >= minRow && tile.row <= maxRow
    && tile.column >= minColumn && tile.column <= maxColumn)
    .map((tile) => tile.index);
  const sum = indices.reduce((total, index) => total + tiles[index].value, 0);
  return { indices, sum, count: indices.length, valid: indices.length > 0 && sum === 10, columns };
}

export function applySumSelection(tiles, evaluation) {
  if (!evaluation.valid) return tiles.map((tile) => ({ ...tile }));
  const removed = new Set(evaluation.indices);
  return tiles.map((tile) => removed.has(tile.index) ? { ...tile, active: false } : { ...tile });
}

const SUM_TEN_RESHUFFLE_ATTEMPTS = 4;

// True when some axis-aligned rectangle of active tiles sums to exactly 10.
// Uses a 2D prefix sum over active values so each rectangle is O(1); short-circuits.
// Mirrors public.gacha_s2_sum_ten_has_move in the server verify RPC — keep in sync.
export function hasValidSumMove(tiles, columns, rows) {
  const cols = columns;
  const rowCount = rows ?? Math.floor(tiles.length / columns);
  const width = cols + 1;
  const pre = new Array(width * (rowCount + 1)).fill(0);
  for (let r = 0; r < rowCount; r += 1) {
    for (let c = 0; c < cols; c += 1) {
      const tile = tiles[r * cols + c];
      const value = tile.active ? tile.value : 0;
      pre[(r + 1) * width + (c + 1)] = value
        + pre[r * width + (c + 1)]
        + pre[(r + 1) * width + c]
        - pre[r * width + c];
    }
  }
  const rectSum = (r1, c1, r2, c2) => pre[(r2 + 1) * width + (c2 + 1)]
    - pre[r1 * width + (c2 + 1)]
    - pre[(r2 + 1) * width + c1]
    + pre[r1 * width + c1];
  for (let r1 = 0; r1 < rowCount; r1 += 1) {
    for (let r2 = r1; r2 < rowCount; r2 += 1) {
      for (let c1 = 0; c1 < cols; c1 += 1) {
        for (let c2 = c1; c2 < cols; c2 += 1) {
          if (rectSum(r1, c1, r2, c2) === 10) return true;
        }
      }
    }
  }
  return false;
}

function sumTenArrangement(sortedAsc, attempt) {
  const m = sortedAsc.length;
  const zigzag = () => {
    const out = [];
    let lo = 0;
    let hi = m - 1;
    while (lo <= hi) {
      out.push(sortedAsc[lo]);
      lo += 1;
      if (lo <= hi) {
        out.push(sortedAsc[hi]);
        hi -= 1;
      }
    }
    return out;
  };
  if (attempt === 0) return zigzag();
  if (attempt === 1) return [...sortedAsc];
  if (attempt === 2) return [...sortedAsc].reverse();
  const z = zigzag();
  return m > 1 ? z.slice(1).concat(z.slice(0, 1)) : z;
}

// Deterministic deadlock rescue: when no sum-10 remains, redistribute the
// remaining active values into their positions using fixed arrangements (no RNG,
// so the server can reproduce it exactly during replay). Returns the reshuffled
// tiles for the first arrangement that restores a valid move, or null if none can
// (caller should end the game). Mirrors public.gacha_s2_sum_ten_reshuffle.
export function reshuffleSumTiles(tiles, columns, rows) {
  const positions = [];
  for (const tile of tiles) if (tile.active) positions.push(tile.index);
  positions.sort((a, b) => a - b);
  if (positions.length === 0) return null;
  const sortedAsc = positions.map((index) => tiles[index].value).sort((a, b) => a - b);
  for (let attempt = 0; attempt < SUM_TEN_RESHUFFLE_ATTEMPTS; attempt += 1) {
    const arranged = sumTenArrangement(sortedAsc, attempt);
    const next = tiles.map((tile) => ({ ...tile }));
    positions.forEach((position, order) => { next[position].value = arranged[order]; });
    if (hasValidSumMove(next, columns, rows)) return next;
  }
  return null;
}

export function calculateMiniGameReward(game, result) {
  if (game === 'memory') {
    if (!result.completed) return 0;
    const rules = MINI_GAME_RULES.memory[result.difficulty] ?? MINI_GAME_RULES.memory.basic;
    return rules.completionReward;
  }
  if (game === 'sumTen') {
    if (result.score <= 0) return 0;
    const rules = MINI_GAME_RULES.sumTen;
    return Math.min(rules.maxReward, rules.baseReward + Math.floor(result.score * rules.rewardPerScore));
  }
  if (game === 'ladder') return MINI_GAME_RULES.ladder.rewards.includes(result.reward) ? result.reward : 0;
  return 0;
}

export function miniGameDateKey(timestamp = Date.now()) {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

export function normalizeMiniGameProgress(progress, now = Date.now()) {
  const date = miniGameDateKey(now);
  if (!progress || progress.date !== date) {
    return {
      date,
      pointsEarned: 0,
      pointsEarnedByGame: { memory: 0, sumTen: 0, ladder: 0 },
      plays: 0,
      bestMemory: 0,
      bestSumTen: 0,
      bestLadder: 0,
    };
  }
  const legacyPoints = Math.max(0, Number(progress.pointsEarned) || 0);
  const storedByGame = progress.pointsEarnedByGame;
  const memoryPoints = Math.min(
    MINI_GAME_RULES.dailyPointCapPerGame,
    Math.max(0, Number(storedByGame?.memory) || (storedByGame ? 0 : legacyPoints)),
  );
  const sumTenPoints = Math.min(
    MINI_GAME_RULES.dailyPointCapPerGame,
    Math.max(0, Number(storedByGame?.sumTen) || 0),
  );
  const ladderPoints = Math.min(
    MINI_GAME_RULES.dailyPointCapPerGame,
    Math.max(0, Number(storedByGame?.ladder) || 0),
  );
  return {
    date,
    pointsEarned: memoryPoints + sumTenPoints + ladderPoints,
    pointsEarnedByGame: { memory: memoryPoints, sumTen: sumTenPoints, ladder: ladderPoints },
    plays: Math.max(0, Number(progress.plays) || 0),
    bestMemory: Math.max(0, Number(progress.bestMemory) || 0),
    bestSumTen: Math.max(0, Number(progress.bestSumTen) || 0),
    bestLadder: Math.max(0, Number(progress.bestLadder) || 0),
  };
}

export function capMiniGameReward(progress, game, reward) {
  const earned = Math.max(0, Number(progress.pointsEarnedByGame?.[game]) || 0);
  const remaining = Math.max(0, MINI_GAME_RULES.dailyPointCapPerGame - earned);
  return Math.min(remaining, Math.max(0, Math.floor(reward)));
}
