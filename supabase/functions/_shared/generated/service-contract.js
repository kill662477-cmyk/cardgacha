export const GAME_API_CONTRACT_VERSION = 1;

export const GAME_COMMAND_TYPES = Object.freeze({
  UPDATE_FORMATION: 'updateFormation',
  CLAIM_ADVENTURE_REWARDS: 'claimAdventureRewards',
  START_ADVENTURE_RUN: 'startAdventureRun',
  FINISH_ADVENTURE_RUN: 'finishAdventureRun',
  CLAIM_QUICK_BATTLE: 'claimQuickBattle',
  PURCHASE_PACK: 'purchasePack',
  PURCHASE_SUPPORT_PACK: 'purchaseSupportPack',
  USE_SUPPORT_ITEM: 'useSupportItem',
  ENHANCE_CARD: 'enhanceCard',
  SET_REPRESENTATIVE_CARD: 'setRepresentativeCard',
  SET_CARD_LOCK: 'setCardLock',
  START_MINIGAME: 'startMinigame',
  FINISH_MINIGAME: 'finishMinigame',
  ATTACK_WORLD_BOSS: 'attackWorldBoss',
  CLAIM_WORLD_BOSS_REWARD: 'claimWorldBossReward',
});

export const GAME_ERROR_CODES = Object.freeze({
  VALIDATION_FAILED: 'VALIDATION_FAILED',
  AUTH_REQUIRED: 'AUTH_REQUIRED',
  FORBIDDEN: 'FORBIDDEN',
  OFFLINE: 'OFFLINE',
  VERSION_CONFLICT: 'VERSION_CONFLICT',
  IDEMPOTENCY_KEY_REUSED: 'IDEMPOTENCY_KEY_REUSED',
  RATE_LIMITED: 'RATE_LIMITED',
  COMMAND_REJECTED: 'COMMAND_REJECTED',
  INTERNAL_ERROR: 'INTERNAL_ERROR',
});

const RETRYABLE_CODES = new Set([
  GAME_ERROR_CODES.OFFLINE,
  GAME_ERROR_CODES.RATE_LIMITED,
  GAME_ERROR_CODES.INTERNAL_ERROR,
]);
const COMMAND_TYPE_SET = new Set(Object.values(GAME_COMMAND_TYPES));
const ERROR_CODE_SET = new Set(Object.values(GAME_ERROR_CODES));
const isRecord = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);
const isNonNegativeInteger = (value) => Number.isSafeInteger(value) && value >= 0;

function addIssue(issues, path, message) {
  issues.push({ path, message });
}

function validateString(issues, value, path, maximum = 128) {
  if (typeof value !== 'string' || !value.trim() || value.length > maximum) addIssue(issues, path, `1~${maximum}자 문자열 필요`);
}

function validatePayload(type, payload, issues) {
  if (!isRecord(payload)) return addIssue(issues, 'payload', '객체 필요');
  const allowedFields = {
    [GAME_COMMAND_TYPES.UPDATE_FORMATION]: ['formation'],
    [GAME_COMMAND_TYPES.CLAIM_ADVENTURE_REWARDS]: ['mode'],
    [GAME_COMMAND_TYPES.START_ADVENTURE_RUN]: [],
    [GAME_COMMAND_TYPES.FINISH_ADVENTURE_RUN]: ['runId'],
    [GAME_COMMAND_TYPES.CLAIM_QUICK_BATTLE]: [],
    [GAME_COMMAND_TYPES.PURCHASE_PACK]: ['productId', 'quantity', 'race'],
    [GAME_COMMAND_TYPES.PURCHASE_SUPPORT_PACK]: ['quantity'],
    [GAME_COMMAND_TYPES.USE_SUPPORT_ITEM]: ['itemId', 'targetCardId', 'race'],
    [GAME_COMMAND_TYPES.ENHANCE_CARD]: ['cardId', 'targetEnhancement', 'materialCardIds', 'boosterId'],
    [GAME_COMMAND_TYPES.SET_REPRESENTATIVE_CARD]: ['cardId'],
    [GAME_COMMAND_TYPES.SET_CARD_LOCK]: ['cardId', 'locked'],
    [GAME_COMMAND_TYPES.START_MINIGAME]: ['game', 'difficulty'],
    [GAME_COMMAND_TYPES.FINISH_MINIGAME]: ['runId', 'inputLog', 'score'],
    [GAME_COMMAND_TYPES.ATTACK_WORLD_BOSS]: ['eventId'],
    [GAME_COMMAND_TYPES.CLAIM_WORLD_BOSS_REWARD]: ['eventId'],
  };
  const allowed = new Set(allowedFields[type] ?? []);
  Object.keys(payload).forEach((field) => {
    if (!allowed.has(field)) addIssue(issues, `payload.${field}`, '계약에 없는 필드');
  });
  switch (type) {
    case GAME_COMMAND_TYPES.UPDATE_FORMATION:
      if (!Array.isArray(payload.formation) || payload.formation.length < 1 || payload.formation.length > 5) {
        addIssue(issues, 'payload.formation', '1~5개 카드 ID 배열 필요');
      } else {
        payload.formation.forEach((cardId, index) => validateString(issues, cardId, `payload.formation.${index}`, 80));
        if (new Set(payload.formation).size !== payload.formation.length) addIssue(issues, 'payload.formation', '중복 카드 ID 불가');
      }
      break;
    case GAME_COMMAND_TYPES.CLAIM_ADVENTURE_REWARDS:
      if (payload.mode !== 'offline') addIssue(issues, 'payload.mode', 'offline required');
      break;
    case GAME_COMMAND_TYPES.START_ADVENTURE_RUN:
    case GAME_COMMAND_TYPES.CLAIM_QUICK_BATTLE:
      break;
    case GAME_COMMAND_TYPES.FINISH_ADVENTURE_RUN:
      validateString(issues, payload.runId, 'payload.runId', 100);
      break;
    case GAME_COMMAND_TYPES.PURCHASE_PACK:
      validateString(issues, payload.productId, 'payload.productId', 80);
      if (![1, 10].includes(payload.quantity)) addIssue(issues, 'payload.quantity', '1 또는 10 필요');
      if (payload.race !== null && payload.race !== undefined && !['저그', '테란', '프로토스'].includes(payload.race)) {
        addIssue(issues, 'payload.race', '유효한 종족 또는 null 필요');
      }
      break;
    case GAME_COMMAND_TYPES.ENHANCE_CARD:
      validateString(issues, payload.cardId, 'payload.cardId', 80);
      if (!Number.isInteger(payload.targetEnhancement) || payload.targetEnhancement < 1 || payload.targetEnhancement > 9) {
        addIssue(issues, 'payload.targetEnhancement', '1~9 정수 필요');
      }
      if (!Array.isArray(payload.materialCardIds) || payload.materialCardIds.length < 1 || payload.materialCardIds.length > 3) {
        addIssue(issues, 'payload.materialCardIds', '1~3개 재료 카드 ID 필요');
      } else payload.materialCardIds.forEach((cardId, index) => validateString(issues, cardId, `payload.materialCardIds.${index}`, 80));
      if (payload.boosterId !== null && payload.boosterId !== undefined) validateString(issues, payload.boosterId, 'payload.boosterId', 80);
      break;
    case GAME_COMMAND_TYPES.PURCHASE_SUPPORT_PACK:
      if (![1, 10].includes(payload.quantity)) addIssue(issues, 'payload.quantity', '1 or 10 required');
      break;
    case GAME_COMMAND_TYPES.USE_SUPPORT_ITEM: {
      validateString(issues, payload.itemId, 'payload.itemId', 80);
      const targetRequired = payload.itemId === 'cardExpPotion';
      const raceRequired = payload.itemId === 'raceTicket';
      if (targetRequired) validateString(issues, payload.targetCardId, 'payload.targetCardId', 80);
      else if (payload.targetCardId !== null && payload.targetCardId !== undefined) addIssue(issues, 'payload.targetCardId', 'targetCardId is only valid for cardExpPotion');
      if (raceRequired && !['저그', '테란', '프로토스'].includes(payload.race)) addIssue(issues, 'payload.race', 'valid race required');
      else if (!raceRequired && payload.race !== null && payload.race !== undefined) addIssue(issues, 'payload.race', 'race is only valid for raceTicket');
      break;
    }
    case GAME_COMMAND_TYPES.SET_REPRESENTATIVE_CARD:
      validateString(issues, payload.cardId, 'payload.cardId', 80);
      break;
    case GAME_COMMAND_TYPES.SET_CARD_LOCK:
      validateString(issues, payload.cardId, 'payload.cardId', 80);
      if (typeof payload.locked !== 'boolean') addIssue(issues, 'payload.locked', 'boolean required');
      break;
    case GAME_COMMAND_TYPES.START_MINIGAME:
      if (!['memory', 'sumTen'].includes(payload.game)) addIssue(issues, 'payload.game', 'memory 또는 sumTen 필요');
      if (payload.game === 'memory' && !['basic', 'advanced'].includes(payload.difficulty)) {
        addIssue(issues, 'payload.difficulty', 'basic 또는 advanced 필요');
      }
      if (payload.game === 'sumTen' && payload.difficulty !== null && payload.difficulty !== undefined) {
        addIssue(issues, 'payload.difficulty', 'sumTen은 난이도 없음');
      }
      break;
    case GAME_COMMAND_TYPES.FINISH_MINIGAME:
      validateString(issues, payload.runId, 'payload.runId', 100);
      if (!Array.isArray(payload.inputLog) || payload.inputLog.length > 500) {
        addIssue(issues, 'payload.inputLog', '최대 500개 입력 배열 필요');
      } else payload.inputLog.forEach((action, index) => {
        if (!isRecord(action) || !isNonNegativeInteger(action.atMs)) {
          addIssue(issues, `payload.inputLog.${index}`, 'atMs가 있는 입력 객체 필요');
          return;
        }
        const memoryAction = isNonNegativeInteger(action.index);
        const sumAction = isNonNegativeInteger(action.start) && isNonNegativeInteger(action.end);
        if (!memoryAction && !sumAction) addIssue(issues, `payload.inputLog.${index}`, '카드 index 또는 선택 start/end 필요');
      });
      if (!isNonNegativeInteger(payload.score)) addIssue(issues, 'payload.score', '0 이상 정수 필요');
      break;
    case GAME_COMMAND_TYPES.ATTACK_WORLD_BOSS:
      validateString(issues, payload.eventId, 'payload.eventId', 100);
      break;
    case GAME_COMMAND_TYPES.CLAIM_WORLD_BOSS_REWARD:
      validateString(issues, payload.eventId, 'payload.eventId', 100);
      break;
    default:
      addIssue(issues, 'type', '지원하지 않는 명령');
  }
}

export function validateGameCommand(command) {
  const issues = [];
  if (!isRecord(command)) return { valid: false, issues: [{ path: '', message: '명령 객체 필요' }] };
  if (command.contractVersion !== GAME_API_CONTRACT_VERSION) addIssue(issues, 'contractVersion', `버전 ${GAME_API_CONTRACT_VERSION} 필요`);
  validateString(issues, command.commandId, 'commandId', 128);
  validateString(issues, command.idempotencyKey, 'idempotencyKey', 128);
  if (command.commandId !== command.idempotencyKey) addIssue(issues, 'idempotencyKey', 'commandId와 동일해야 함');
  if (!COMMAND_TYPE_SET.has(command.type)) addIssue(issues, 'type', '지원하지 않는 명령');
  if (!isNonNegativeInteger(command.expectedRevision)) addIssue(issues, 'expectedRevision', '0 이상 정수 필요');
  if (!isNonNegativeInteger(command.clientSentAt)) addIssue(issues, 'clientSentAt', '0 이상 정수 필요');
  validatePayload(command.type, command.payload, issues);
  const allowed = new Set(['contractVersion', 'commandId', 'idempotencyKey', 'type', 'expectedRevision', 'clientSentAt', 'payload']);
  Object.keys(command).forEach((field) => {
    if (!allowed.has(field)) addIssue(issues, field, '계약에 없는 필드');
  });
  return { valid: issues.length === 0, issues };
}

export function createGameCommand({ type, payload, expectedRevision, idempotencyKey, clientSentAt }) {
  const command = {
    contractVersion: GAME_API_CONTRACT_VERSION,
    commandId: idempotencyKey,
    idempotencyKey,
    type,
    expectedRevision,
    clientSentAt,
    payload,
  };
  const validation = validateGameCommand(command);
  if (!validation.valid) {
    const details = validation.issues.map(({ path, message }) => `${path || '<root>'}: ${message}`).join('; ');
    throw new Error(`Invalid game command: ${details}`);
  }
  return command;
}

export function createGameSuccess({ command, revision, serverTime, serverSeed, snapshot, result = {} }) {
  return {
    contractVersion: GAME_API_CONTRACT_VERSION,
    ok: true,
    commandId: command.commandId,
    idempotencyKey: command.idempotencyKey,
    revision,
    serverTime,
    serverSeed,
    snapshot,
    result,
  };
}

export function createGameError({ command = null, code, message, serverTime, revision = null, latestSnapshot = null, details = null }) {
  return {
    contractVersion: GAME_API_CONTRACT_VERSION,
    ok: false,
    commandId: command?.commandId ?? null,
    idempotencyKey: command?.idempotencyKey ?? null,
    code,
    message,
    retryable: RETRYABLE_CODES.has(code),
    serverTime,
    revision,
    latestSnapshot,
    details,
  };
}

export function validateGameResponse(response) {
  const issues = [];
  if (!isRecord(response)) return { valid: false, issues: [{ path: '', message: '응답 객체 필요' }] };
  if (response.contractVersion !== GAME_API_CONTRACT_VERSION) addIssue(issues, 'contractVersion', `버전 ${GAME_API_CONTRACT_VERSION} 필요`);
  if (typeof response.ok !== 'boolean') addIssue(issues, 'ok', 'boolean 필요');
  if (response.commandId !== null) validateString(issues, response.commandId, 'commandId', 128);
  if (response.idempotencyKey !== null) validateString(issues, response.idempotencyKey, 'idempotencyKey', 128);
  if (response.commandId !== response.idempotencyKey) addIssue(issues, 'idempotencyKey', 'commandId와 동일해야 함');
  if (!isNonNegativeInteger(response.serverTime)) addIssue(issues, 'serverTime', '0 이상 정수 필요');

  if (response.ok === true) {
    if (!isNonNegativeInteger(response.revision)) addIssue(issues, 'revision', '0 이상 정수 필요');
    if (!isNonNegativeInteger(response.serverSeed) || response.serverSeed > 0xffffffff) addIssue(issues, 'serverSeed', '32비트 시드 필요');
    if (!isRecord(response.snapshot)) addIssue(issues, 'snapshot', '상태 객체 필요');
    else if (response.snapshot.revision !== response.revision) addIssue(issues, 'snapshot.revision', '응답 revision과 일치해야 함');
    if (!isRecord(response.result)) addIssue(issues, 'result', '결과 객체 필요');
  } else if (response.ok === false) {
    if (!ERROR_CODE_SET.has(response.code)) addIssue(issues, 'code', '지원하지 않는 오류 코드');
    if (typeof response.message !== 'string' || !response.message) addIssue(issues, 'message', '오류 메시지 필요');
    if (typeof response.retryable !== 'boolean') addIssue(issues, 'retryable', 'boolean 필요');
    if (response.revision !== null && !isNonNegativeInteger(response.revision)) addIssue(issues, 'revision', '0 이상 정수 또는 null 필요');
    if (response.latestSnapshot !== null && !isRecord(response.latestSnapshot)) addIssue(issues, 'latestSnapshot', '상태 객체 또는 null 필요');
    if (response.code === GAME_ERROR_CODES.VERSION_CONFLICT && !isRecord(response.latestSnapshot)) {
      addIssue(issues, 'latestSnapshot', '버전 충돌에는 최신 상태 필요');
    }
  }
  return { valid: issues.length === 0, issues };
}

export function isRetryableGameError(response) {
  return Boolean(response && response.ok === false && response.retryable && RETRYABLE_CODES.has(response.code));
}

export function stableCommandFingerprint(command) {
  const canonicalize = (value) => {
    if (Array.isArray(value)) return value.map(canonicalize);
    if (!isRecord(value)) return value;
    return Object.keys(value).sort().reduce((result, key) => {
      result[key] = canonicalize(value[key]);
      return result;
    }, {});
  };
  const normalized = {
    contractVersion: command.contractVersion,
    type: command.type,
    expectedRevision: command.expectedRevision,
    payload: command.payload,
  };
  return JSON.stringify(canonicalize(normalized));
}
