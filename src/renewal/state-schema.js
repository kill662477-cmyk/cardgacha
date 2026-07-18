import {
  ADVENTURE_RULES, ENHANCEMENT, EX_DISTRIBUTION_RULES, GAME_RULES, MINI_GAME_RULES, REWARD_RULES,
  SUPPORT_ITEMS, WORLD_BOSS_RULES,
} from './config.js';

export const GAME_STATE_SCHEMA_VERSION = 2;

export const SERVER_AUTHORITY_FIELDS = Object.freeze([
  // nolevel-1(v2): accountLevel, accountExp 제거. 전투력은 순수 카드 기반.
  'schemaVersion', 'revision', 'nickname',
  'actionEnergy', 'maxActionEnergy', 'lastEnergyAt', 'points',
  'clearedStage', 'pendingPoints', 'lastRewardAt', 'quickBattle', 'adventureRuns',
  'adventureRun', 'cardProgress', 'cardCopies', 'cardLocks', 'collectionRecords',
  'supportItems', 'activeBuffs', 'shopTransactions', 'enhancementAttempts',
  'miniGames', 'worldBoss', 'exMilestoneClaims', 'representativeCardId', 'formation',
  'formationPresets', 'activeFormationPresetId', 'miniGameRuns', 'powerRanking',
]);

export const CLIENT_CACHE_FIELDS = Object.freeze(['currentStage', 'autoBattle', 'soundEnabled']);

const isRecord = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);
const isFiniteNumber = (value) => typeof value === 'number' && Number.isFinite(value);
const isIntegerBetween = (value, minimum, maximum = Number.MAX_SAFE_INTEGER) => (
  Number.isInteger(value) && value >= minimum && value <= maximum
);

function issue(issues, path, message) {
  issues.push({ path, message });
}

function validateNumber(issues, state, field, minimum = 0, maximum = Number.MAX_SAFE_INTEGER) {
  if (!isIntegerBetween(state[field], minimum, maximum)) issue(issues, field, `${minimum}~${maximum} 정수 필요`);
}

function validateBooleanRecord(issues, value, path, cardIds) {
  if (!isRecord(value)) return issue(issues, path, '객체 필요');
  Object.entries(value).forEach(([cardId, entry]) => {
    if (cardIds && !cardIds.has(cardId)) issue(issues, `${path}.${cardId}`, '존재하지 않는 카드 ID');
    if (typeof entry !== 'boolean') issue(issues, `${path}.${cardId}`, 'boolean 필요');
  });
}

function validateCountRecord(issues, value, path, cardIds) {
  if (!isRecord(value)) return issue(issues, path, '객체 필요');
  Object.entries(value).forEach(([cardId, entry]) => {
    if (cardIds && !cardIds.has(cardId)) issue(issues, `${path}.${cardId}`, '존재하지 않는 카드 ID');
    if (!isIntegerBetween(entry, 0)) issue(issues, `${path}.${cardId}`, '0 이상 정수 필요');
  });
}

function validateCardProgress(issues, value, cardIds) {
  if (!isRecord(value)) return issue(issues, 'cardProgress', '객체 필요');
  Object.entries(value).forEach(([cardId, progress]) => {
    const path = `cardProgress.${cardId}`;
    if (cardIds && !cardIds.has(cardId)) issue(issues, path, '존재하지 않는 카드 ID');
    if (!isRecord(progress)) return issue(issues, path, '객체 필요');
    if (!isIntegerBetween(progress.enhancement, 0, 9)) issue(issues, `${path}.enhancement`, '0~9 정수 필요');
    const maximumExp = ENHANCEMENT.expRequirements[progress.enhancement] ?? 0;
    if (!isIntegerBetween(progress.exp, 0, maximumExp)) issue(issues, `${path}.exp`, `0~${maximumExp} 정수 필요`);
  });
}

function validateSupportItems(issues, value) {
  if (!isRecord(value)) return issue(issues, 'supportItems', '객체 필요');
  const itemIds = new Set(Object.keys(SUPPORT_ITEMS));
  itemIds.forEach((itemId) => {
    if (!Object.hasOwn(value, itemId)) issue(issues, `supportItems.${itemId}`, '필수 아이템 수량 누락');
  });
  Object.entries(value).forEach(([itemId, count]) => {
    if (!itemIds.has(itemId)) issue(issues, `supportItems.${itemId}`, '존재하지 않는 아이템 ID');
    if (!isIntegerBetween(count, 0)) issue(issues, `supportItems.${itemId}`, '0 이상 정수 필요');
  });
}

function validateAdventure(issues, state) {
  const runs = state.adventureRuns;
  if (!isRecord(runs)) issue(issues, 'adventureRuns', '객체 필요');
  else {
    if (!isIntegerBetween(runs.windowStartedAt, 0)) issue(issues, 'adventureRuns.windowStartedAt', '0 이상 정수 필요');
    if (!isIntegerBetween(runs.count, 0, ADVENTURE_RULES.maxRunsPerWindow)) issue(issues, 'adventureRuns.count', '허용 횟수 초과');
  }

  const run = state.adventureRun;
  if (!isRecord(run)) return issue(issues, 'adventureRun', '객체 필요');
  if (typeof run.active !== 'boolean') issue(issues, 'adventureRun.active', 'boolean 필요');
  if (!isIntegerBetween(run.currentStage, 1, REWARD_RULES.maxStage)) issue(issues, 'adventureRun.currentStage', '1~50 정수 필요');
  if (!isIntegerBetween(run.clearedStages, 0, REWARD_RULES.maxStage)) issue(issues, 'adventureRun.clearedStages', '0~50 정수 필요');
  if (!isIntegerBetween(run.startedAt, 0)) issue(issues, 'adventureRun.startedAt', '0 이상 정수 필요');
  if (run.runId !== undefined && (typeof run.runId !== 'string' || !run.runId.trim() || run.runId.length > 100)) {
    issue(issues, 'adventureRun.runId', '유효한 서버 실행 ID 필요');
  }
  if (run.verifiedClearedStages !== undefined
    && !isIntegerBetween(run.verifiedClearedStages, 0, REWARD_RULES.maxStage)) {
    issue(issues, 'adventureRun.verifiedClearedStages', '0~50 정수 필요');
  }
  if (run.verificationDigest !== undefined
    && (typeof run.verificationDigest !== 'string' || !/^[0-9a-f]{64}$/i.test(run.verificationDigest))) {
    issue(issues, 'adventureRun.verificationDigest', '64자리 검증 해시 필요');
  }
  if (run.active && run.currentStage !== run.clearedStages + 1) issue(issues, 'adventureRun', '진행 단계와 클리어 수 불일치');
  if (!run.active && (run.currentStage !== 1 || run.clearedStages !== 0 || run.startedAt !== 0)) {
    issue(issues, 'adventureRun', '비활성 런은 초기 상태 필요');
  }
  if (!run.active && ['runId', 'verifiedClearedStages', 'verificationDigest'].some((field) => run[field] !== undefined)) {
    issue(issues, 'adventureRun', '비활성 런에 서버 실행 정보 사용 불가');
  }
}

function validateDailyProgress(issues, value, path, fields) {
  if (!isRecord(value)) return issue(issues, path, '객체 필요');
  if (typeof value.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value.date)) issue(issues, `${path}.date`, 'YYYY-MM-DD 필요');
  fields.forEach(([field, maximum]) => {
    if (!isIntegerBetween(value[field], 0, maximum)) issue(issues, `${path}.${field}`, '허용 범위 정수 필요');
  });
}

function validateWorldBoss(issues, value) {
  if (!isRecord(value)) return issue(issues, 'worldBoss', '객체 필요');
  if (typeof value.eventId !== 'string' || value.eventId.length === 0) issue(issues, 'worldBoss.eventId', '회차 ID 필요');
  ['startedAt', 'endsAt', 'bestDamage', 'totalDamage', 'lastDamage'].forEach((field) => {
    if (!isIntegerBetween(value[field], 0)) issue(issues, `worldBoss.${field}`, '0 이상 정수 필요');
  });
  if (!isIntegerBetween(value.attempts, 0, WORLD_BOSS_RULES.maxAttempts)) issue(issues, 'worldBoss.attempts', '도전 횟수 초과');
  if (!isIntegerBetween(value.claimedTier, -1, WORLD_BOSS_RULES.rewardTiers.length - 1)) issue(issues, 'worldBoss.claimedTier', '보상 단계 범위 초과');
  if (isFiniteNumber(value.startedAt) && isFiniteNumber(value.endsAt) && value.endsAt <= value.startedAt) {
    issue(issues, 'worldBoss.endsAt', '시작 시각보다 뒤여야 함');
  }
}

function validateFormation(issues, formation, path, cardIds) {
  if (!Array.isArray(formation) || formation.length > GAME_RULES.formationSize) return issue(issues, path, '최대 5개 카드 배열 필요');
  if (new Set(formation).size !== formation.length) issue(issues, path, '중복 카드 ID 불가');
  formation.forEach((cardId, index) => {
    if (typeof cardId !== 'string' || (cardIds && !cardIds.has(cardId))) issue(issues, `${path}.${index}`, '유효한 카드 ID 필요');
  });
}

function validateReservedServerState(issues, state, cardIds) {
  if (!isRecord(state.formationPresets)) issue(issues, 'formationPresets', '객체 필요');
  else {
    if (Object.keys(state.formationPresets).length > 5) issue(issues, 'formationPresets', '프리셋 최대 5개');
    Object.entries(state.formationPresets).forEach(([presetId, formation]) => {
      if (!presetId.trim()) issue(issues, 'formationPresets', '프리셋 ID 필요');
      validateFormation(issues, formation, `formationPresets.${presetId}`, cardIds);
    });
  }
  if (state.activeFormationPresetId !== null && typeof state.activeFormationPresetId !== 'string') {
    issue(issues, 'activeFormationPresetId', '프리셋 ID 또는 null 필요');
  } else if (state.activeFormationPresetId && !Object.hasOwn(state.formationPresets ?? {}, state.activeFormationPresetId)) {
    issue(issues, 'activeFormationPresetId', '존재하지 않는 프리셋 ID');
  }

  if (!Array.isArray(state.miniGameRuns) || state.miniGameRuns.length > 20) issue(issues, 'miniGameRuns', '최근 검증 로그 최대 20개 필요');
  else state.miniGameRuns.forEach((run, index) => {
    const path = `miniGameRuns.${index}`;
    if (!isRecord(run)) return issue(issues, path, '객체 필요');
    if (typeof run.runId !== 'string' || !run.runId.trim() || run.runId.length > 100) issue(issues, `${path}.runId`, '실행 ID 필요');
    if (!['memory', 'sumTen'].includes(run.game)) issue(issues, `${path}.game`, '게임 종류 오류');
    if (run.game === 'memory' && !['basic', 'advanced'].includes(run.difficulty)) issue(issues, `${path}.difficulty`, '메모리 난이도 오류');
    if (run.game === 'sumTen' && run.difficulty !== null) issue(issues, `${path}.difficulty`, '합계 10은 난이도 없음');
    if (!isIntegerBetween(run.seed, 0, 0xffffffff)) issue(issues, `${path}.seed`, '32비트 정수 시드 필요');
    if (run.status !== 'active') issue(issues, `${path}.status`, '진행 중 실행만 스냅샷 허용');
    if (!Array.isArray(run.board)) issue(issues, `${path}.board`, '서버 보드 배열 필요');
    else if (run.game === 'memory') {
      const expected = run.difficulty === 'advanced' ? 36 : 16;
      if (run.board.length !== expected || run.board.some((cardId) => typeof cardId !== 'string' || !cardId)) {
        issue(issues, `${path}.board`, `${expected}장 카드 ID 배열 필요`);
      }
    } else if (run.game === 'sumTen'
      && (run.board.length !== 170 || run.board.some((value) => !isIntegerBetween(value, 1, 9)))) {
      issue(issues, `${path}.board`, '1~9 숫자 170개 필요');
    }
    if (!isIntegerBetween(run.timeLimit, 1, 300)) issue(issues, `${path}.timeLimit`, '1~300초 제한 필요');
    if (!isIntegerBetween(run.startedAt, 0) || !isIntegerBetween(run.expiresAt, 0)) issue(issues, path, '실행 시각 오류');
    if (run.expiresAt <= run.startedAt) issue(issues, `${path}.expiresAt`, '시작 이후 만료 시각 필요');
  });

  const ranking = state.powerRanking;
  if (!isRecord(ranking)) return issue(issues, 'powerRanking', '객체 필요');
  if (typeof ranking.seasonId !== 'string' || !ranking.seasonId) issue(issues, 'powerRanking.seasonId', '시즌 ID 필요');
  ['snapshotAt', 'power', 'population'].forEach((field) => {
    if (!isIntegerBetween(ranking[field], 0)) issue(issues, `powerRanking.${field}`, '0 이상 정수 필요');
  });
  if (ranking.rank !== null && !isIntegerBetween(ranking.rank, 1)) issue(issues, 'powerRanking.rank', '1 이상 정수 또는 null 필요');
  if (ranking.rank !== null && ranking.rank > ranking.population) issue(issues, 'powerRanking.rank', '전체 인원보다 클 수 없음');
}

export function migrateGameState(rawState) {
  if (!isRecord(rawState)) return { ok: false, fromVersion: null, state: null, issues: [{ path: '', message: '상태 객체 필요' }] };
  const fromVersion = rawState.schemaVersion ?? 0;
  if (!Number.isInteger(fromVersion) || fromVersion < 0 || fromVersion > GAME_STATE_SCHEMA_VERSION) {
    return { ok: false, fromVersion, state: null, issues: [{ path: 'schemaVersion', message: '지원하지 않는 상태 버전' }] };
  }
  const state = { ...rawState };
  const removedGrowthMaterials = Object.hasOwn(state, 'growthMaterials');
  delete state.growthMaterials;
  let addedResetItems = false;
  if (isRecord(state.supportItems)) {
    state.supportItems = { ...state.supportItems };
    ['adventureRunReset', 'quickBattleReset'].forEach((itemId) => {
      if (!Object.hasOwn(state.supportItems, itemId)) {
        state.supportItems[itemId] = 0;
        addedResetItems = true;
      }
    });
  }
  let addedMiniGameBreakdown = false;
  if (isRecord(state.miniGames) && !isRecord(state.miniGames.pointsEarnedByGame)) {
    const legacyPoints = Math.max(0, Math.floor(Number(state.miniGames.pointsEarned) || 0));
    const memoryPoints = Math.min(MINI_GAME_RULES.dailyPointCapPerGame, legacyPoints);
    state.miniGames = {
      ...state.miniGames,
      pointsEarned: legacyPoints,
      pointsEarnedByGame: {
        memory: memoryPoints,
        sumTen: Math.min(MINI_GAME_RULES.dailyPointCapPerGame, Math.max(0, legacyPoints - memoryPoints)),
      },
    };
    addedMiniGameBreakdown = true;
  }
  // nolevel-1: v1 → v2 마이그레이션. accountLevel, accountExp 필드 제거.
  let removedAccountLevel = false;
  if (fromVersion <= 1) {
    if (Object.hasOwn(state, 'accountLevel')) { delete state.accountLevel; removedAccountLevel = true; }
    if (Object.hasOwn(state, 'accountExp')) { delete state.accountExp; removedAccountLevel = true; }
  }
  if (fromVersion < GAME_STATE_SCHEMA_VERSION) {
    state.schemaVersion = GAME_STATE_SCHEMA_VERSION;
  }
  if (fromVersion === 0) {
    state.revision = isIntegerBetween(state.revision, 0) ? state.revision : 0;
  }
  return {
    ok: true,
    fromVersion,
    migrated: fromVersion !== GAME_STATE_SCHEMA_VERSION || removedGrowthMaterials || addedResetItems || addedMiniGameBreakdown || removedAccountLevel,
    state,
    issues: [],
  };
}

export function validateGameState(state, options = {}) {
  const issues = [];
  const cardIds = options.cardIds ? new Set(options.cardIds) : null;
  if (!isRecord(state)) return { valid: false, issues: [{ path: '', message: '상태 객체 필요' }] };
  if (state.schemaVersion !== GAME_STATE_SCHEMA_VERSION) issue(issues, 'schemaVersion', `버전 ${GAME_STATE_SCHEMA_VERSION} 필요`);
  validateNumber(issues, state, 'revision');
  if (typeof state.nickname !== 'string' || state.nickname.trim().length === 0 || state.nickname.length > 40) issue(issues, 'nickname', '1~40자 필요');
  validateNumber(issues, state, 'actionEnergy', 0, REWARD_RULES.maxActionEnergy * 2);
  validateNumber(issues, state, 'maxActionEnergy', 1, REWARD_RULES.maxActionEnergy);
  validateNumber(issues, state, 'lastEnergyAt');
  validateNumber(issues, state, 'points');
  validateNumber(issues, state, 'currentStage', 1, REWARD_RULES.maxStage);
  validateNumber(issues, state, 'clearedStage', 0, REWARD_RULES.maxStage);
  validateNumber(issues, state, 'pendingPoints');
  validateNumber(issues, state, 'lastRewardAt');
  validateNumber(issues, state, 'shopTransactions');
  validateNumber(issues, state, 'enhancementAttempts');
  if (typeof state.soundEnabled !== 'boolean') issue(issues, 'soundEnabled', 'boolean 필요');
  if (typeof state.autoBattle !== 'boolean') issue(issues, 'autoBattle', 'boolean 필요');

  validateDailyProgress(issues, state.quickBattle, 'quickBattle', [['count', REWARD_RULES.quickBattleDailyLimit]]);
  validateAdventure(issues, state);
  validateCardProgress(issues, state.cardProgress, cardIds);
  validateCountRecord(issues, state.cardCopies, 'cardCopies', cardIds);
  validateBooleanRecord(issues, state.cardLocks, 'cardLocks', cardIds);
  validateBooleanRecord(issues, state.collectionRecords, 'collectionRecords', cardIds);
  validateSupportItems(issues, state.supportItems);

  if (!isRecord(state.activeBuffs)) issue(issues, 'activeBuffs', '객체 필요');
  else {
    ['cardExpStartAt', 'cardExpEndAt'].forEach((field) => {
      if (!isIntegerBetween(state.activeBuffs[field], 0)) issue(issues, `activeBuffs.${field}`, '0 이상 정수 필요');
    });
    if (state.activeBuffs.cardExpEndAt < state.activeBuffs.cardExpStartAt) issue(issues, 'activeBuffs', '버프 종료 시각 오류');
  }

  validateDailyProgress(issues, state.miniGames, 'miniGames', [
    ['pointsEarned', MINI_GAME_RULES.dailyPointCapPerGame * 2], ['plays', Number.MAX_SAFE_INTEGER],
    ['bestMemory', Number.MAX_SAFE_INTEGER], ['bestSumTen', Number.MAX_SAFE_INTEGER],
  ]);
  const miniGameBreakdown = state.miniGames?.pointsEarnedByGame;
  if (!isRecord(miniGameBreakdown)) issue(issues, 'miniGames.pointsEarnedByGame', '게임별 포인트 객체 필요');
  else {
    ['memory', 'sumTen'].forEach((game) => {
      if (!isIntegerBetween(miniGameBreakdown[game], 0, MINI_GAME_RULES.dailyPointCapPerGame)) {
        issue(issues, `miniGames.pointsEarnedByGame.${game}`, `0~${MINI_GAME_RULES.dailyPointCapPerGame} 정수 필요`);
      }
    });
    Object.keys(miniGameBreakdown).forEach((game) => {
      if (!['memory', 'sumTen'].includes(game)) issue(issues, `miniGames.pointsEarnedByGame.${game}`, '존재하지 않는 미니게임');
    });
    if (isIntegerBetween(miniGameBreakdown.memory, 0) && isIntegerBetween(miniGameBreakdown.sumTen, 0)
      && state.miniGames.pointsEarned !== miniGameBreakdown.memory + miniGameBreakdown.sumTen) {
      issue(issues, 'miniGames.pointsEarned', '게임별 포인트 합계와 불일치');
    }
  }
  validateWorldBoss(issues, state.worldBoss);
  if (!isRecord(state.exMilestoneClaims)) issue(issues, 'exMilestoneClaims', '객체 필요');
  else Object.entries(state.exMilestoneClaims).forEach(([stage, cardId]) => {
    const milestone = EX_DISTRIBUTION_RULES.milestones.find((entry) => String(entry.clearedStage) === stage);
    if (!milestone || milestone.cardId !== cardId) issue(issues, `exMilestoneClaims.${stage}`, 'EX 마일스톤 지급 기록 오류');
  });

  if (state.representativeCardId !== null && typeof state.representativeCardId !== 'string') {
    issue(issues, 'representativeCardId', '카드 ID 또는 null 필요');
  } else if (cardIds && state.representativeCardId && !cardIds.has(state.representativeCardId)) {
    issue(issues, 'representativeCardId', '존재하지 않는 카드 ID');
  }
  validateFormation(issues, state.formation, 'formation', cardIds);
  validateReservedServerState(issues, state, cardIds);
  if (options.requireOwnedCards && isRecord(state.cardCopies) && Array.isArray(state.formation)) {
    if (state.representativeCardId && (state.cardCopies[state.representativeCardId] ?? 0) <= 0) issue(issues, 'representativeCardId', '미보유 카드 지정 불가');
    state.formation.forEach((cardId, index) => {
      if ((state.cardCopies[cardId] ?? 0) <= 0) issue(issues, `formation.${index}`, '미보유 카드 편성 불가');
    });
  }

  const declaredFields = new Set([...SERVER_AUTHORITY_FIELDS, ...CLIENT_CACHE_FIELDS]);
  Object.keys(state).forEach((field) => {
    if (!declaredFields.has(field)) issue(issues, field, 'v2에 선언되지 않은 필드');
  });
  return { valid: issues.length === 0, issues };
}

export function assertValidGameState(state, options = {}) {
  const result = validateGameState(state, options);
  if (!result.valid) {
    const details = result.issues.slice(0, 5).map(({ path, message }) => `${path || '<root>'}: ${message}`).join('; ');
    throw new Error(`Invalid game state v${GAME_STATE_SCHEMA_VERSION}: ${details}`);
  }
  return state;
}
