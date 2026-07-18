import { createWorldBossProgress } from './worldboss.js';
import { REWARD_RULES } from './config.js';
import { assertValidGameState, GAME_STATE_SCHEMA_VERSION, migrateGameState, validateGameState } from './state-schema.js';

const STORAGE_KEY = 'calm-monstarz-renewal-slice-v1';

function localDateKey(timestamp = Date.now()) {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

export function createDefaultState(now = Date.now()) {
  return {
    schemaVersion: GAME_STATE_SCHEMA_VERSION,
    revision: 0,
    nickname: '방송국장_세린',
    actionEnergy: 64,
    maxActionEnergy: REWARD_RULES.maxActionEnergy,
    lastEnergyAt: now,
    points: 8450,
    currentStage: 1,
    clearedStage: 0,
    pendingPoints: 0,
    lastRewardAt: now - 2 * 60 * 60 * 1000,
    quickBattle: { date: localDateKey(now), count: 0 },
    adventureRuns: { windowStartedAt: 0, count: 0 },
    adventureRun: { active: false, currentStage: 1, clearedStages: 0, startedAt: 0 },
    cardProgress: {},
    cardCopies: {},
    cardLocks: {},
    collectionRecords: {},
    supportItems: {
      energySmall: 1, energyMedium: 0, energyLarge: 0,
      enhance5: 2, enhance10: 1, destructionGuard: 1,
      cardExpPotion: 1, exp30m: 1, exp2h: 0,
      generalTicket: 1, eliteTicket: 0, raceTicket: 0, premiumTicket: 0,
      adventureRunReset: 0, quickBattleReset: 0,
    },
    activeBuffs: { cardExpStartAt: 0, cardExpEndAt: 0 },
    shopTransactions: 0,
    enhancementAttempts: 0,
    miniGames: {
      date: localDateKey(now),
      pointsEarned: 0,
      pointsEarnedByGame: { memory: 0, sumTen: 0 },
      plays: 0,
      bestMemory: 0,
      bestSumTen: 0,
    },
    worldBoss: createWorldBossProgress(now),
    exMilestoneClaims: {},
    soundEnabled: true,
    autoBattle: false,
    representativeCardId: 'kimyunhwan-2',
    formation: ['kimyunhwan-2', 'kimyunhwan-1', 'tomato-1', 'jidudu-2', 'byeonhyeonje-1'],
    formationPresets: {},
    activeFormationPresetId: null,
    miniGameRuns: [],
    powerRanking: { seasonId: 'local-preview', snapshotAt: 0, power: 0, rank: null, population: 1500 },
  };
}

export const DEFAULT_STATE = createDefaultState();

export function loadState(now = Date.now()) {
  const base = createDefaultState(now);
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    const migration = migrateGameState(saved);
    if (!migration.ok) return base;
    const source = migration.fromVersion === 0
      ? Object.fromEntries(Object.keys(base)
        .filter((field) => Object.hasOwn(migration.state, field))
        .map((field) => [field, migration.state[field]]))
      : migration.state;
    const merged = migration.fromVersion === 0 ? {
      ...base,
      ...source,
      quickBattle: { ...base.quickBattle, ...(source.quickBattle ?? {}) },
      adventureRuns: { ...base.adventureRuns, ...(source.adventureRuns ?? {}) },
      adventureRun: { ...base.adventureRun, ...(source.adventureRun ?? {}) },
      cardProgress: { ...base.cardProgress, ...(source.cardProgress ?? {}) },
      cardCopies: { ...base.cardCopies, ...(source.cardCopies ?? {}) },
      cardLocks: { ...base.cardLocks, ...(source.cardLocks ?? {}) },
      collectionRecords: { ...base.collectionRecords, ...(source.collectionRecords ?? {}) },
      supportItems: { ...base.supportItems, ...(source.supportItems ?? {}) },
      activeBuffs: { ...base.activeBuffs, ...(source.activeBuffs ?? {}) },
      miniGames: { ...base.miniGames, ...(source.miniGames ?? {}) },
      worldBoss: { ...base.worldBoss, ...(source.worldBoss ?? {}) },
      exMilestoneClaims: { ...base.exMilestoneClaims, ...(source.exMilestoneClaims ?? {}) },
      formationPresets: { ...base.formationPresets, ...(source.formationPresets ?? {}) },
      miniGameRuns: Array.isArray(source.miniGameRuns) ? source.miniGameRuns : base.miniGameRuns,
      powerRanking: { ...base.powerRanking, ...(source.powerRanking ?? {}) },
    } : source;
    return validateGameState(merged).valid ? merged : base;
  } catch {
    return base;
  }
}

export function saveState(state) {
  const snapshot = {
    ...state,
    schemaVersion: GAME_STATE_SCHEMA_VERSION,
    revision: Math.max(0, Number(state.revision) || 0) + 1,
  };
  assertValidGameState(snapshot);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot));
  state.schemaVersion = snapshot.schemaVersion;
  state.revision = snapshot.revision;
}

export function resetState(now = Date.now()) {
  localStorage.removeItem(STORAGE_KEY);
  return createDefaultState(now);
}
