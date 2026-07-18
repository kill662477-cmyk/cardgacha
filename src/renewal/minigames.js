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
      pointsEarnedByGame: { memory: 0, sumTen: 0 },
      plays: 0,
      bestMemory: 0,
      bestSumTen: 0,
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
  return {
    date,
    pointsEarned: memoryPoints + sumTenPoints,
    pointsEarnedByGame: { memory: memoryPoints, sumTen: sumTenPoints },
    plays: Math.max(0, Number(progress.plays) || 0),
    bestMemory: Math.max(0, Number(progress.bestMemory) || 0),
    bestSumTen: Math.max(0, Number(progress.bestSumTen) || 0),
  };
}

export function capMiniGameReward(progress, game, reward) {
  const earned = Math.max(0, Number(progress.pointsEarnedByGame?.[game]) || 0);
  const remaining = Math.max(0, MINI_GAME_RULES.dailyPointCapPerGame - earned);
  return Math.min(remaining, Math.max(0, Math.floor(reward)));
}
