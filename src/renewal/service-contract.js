export const GAME_API_CONTRACT_VERSION = 1;

// 보급품 분해 1회 최대 수량. 단가 최고치(1,200P)를 곱해도 정수 범위에 여유가 크다.
export const SUPPORT_ITEM_DISMANTLE_MAX_COUNT = 100000;

export const GAME_COMMAND_TYPES = Object.freeze({
  UPDATE_FORMATION: 'updateFormation',
  // 편성 프리셋(최대 5개). 상태 필드(formationPresets/activeFormationPresetId)와 5개 상한은
  // state-schema 에 이미 있었는데 쓰는 명령이 없어 항상 비어 있었다.
  SAVE_FORMATION_PRESET: 'saveFormationPreset',
  APPLY_FORMATION_PRESET: 'applyFormationPreset',
  DELETE_FORMATION_PRESET: 'deleteFormationPreset',
  CLAIM_ADVENTURE_REWARDS: 'claimAdventureRewards',
  START_ADVENTURE_RUN: 'startAdventureRun',
  FINISH_ADVENTURE_RUN: 'finishAdventureRun',
  CLAIM_QUICK_BATTLE: 'claimQuickBattle',
  PURCHASE_PACK: 'purchasePack',
  PURCHASE_SUPPORT_PACK: 'purchaseSupportPack',
  USE_SUPPORT_ITEM: 'useSupportItem',
  REDEEM_CARD_SELECTOR: 'redeemCardSelector',
  ENHANCE_CARD: 'enhanceCard',
  DISMANTLE_CARDS: 'dismantleCards',
  DISMANTLE_SUPPORT_ITEM: 'dismantleSupportItem',
  SET_REPRESENTATIVE_CARD: 'setRepresentativeCard',
  SET_CARD_LOCK: 'setCardLock',
  START_MINIGAME: 'startMinigame',
  FINISH_MINIGAME: 'finishMinigame',
  PLAY_LADDER: 'playLadder',
  BUY_LOTTO_TICKET: 'buyLottoTicket',
  ATTACK_WORLD_BOSS: 'attackWorldBoss',
  CLAIM_WORLD_BOSS_REWARD: 'claimWorldBossReward',
  // 길드(PDB-16 M1)
  CREATE_GUILD: 'createGuild',
  DISBAND_GUILD: 'disbandGuild',
  UPDATE_GUILD_SETTINGS: 'updateGuildSettings',
  REQUEST_JOIN_GUILD: 'requestJoinGuild',
  CANCEL_JOIN_REQUEST: 'cancelJoinRequest',
  RESOLVE_JOIN_REQUEST: 'resolveJoinRequest',
  LEAVE_GUILD: 'leaveGuild',
  KICK_GUILD_MEMBER: 'kickGuildMember',
  SET_GUILD_MEMBER_ROLE: 'setGuildMemberRole',
  CLAIM_GUILD_WEEKLY_REWARD: 'claimGuildWeeklyReward',
  ATTACK_GUILD_RAID: 'attackGuildRaid',
  CLAIM_GUILD_RAID_REWARD: 'claimGuildRaidReward',
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
    [GAME_COMMAND_TYPES.SAVE_FORMATION_PRESET]: ['presetId', 'formation'],
    [GAME_COMMAND_TYPES.APPLY_FORMATION_PRESET]: ['presetId'],
    [GAME_COMMAND_TYPES.DELETE_FORMATION_PRESET]: ['presetId'],
    [GAME_COMMAND_TYPES.CLAIM_ADVENTURE_REWARDS]: ['mode'],
    [GAME_COMMAND_TYPES.START_ADVENTURE_RUN]: ['mode'],
    [GAME_COMMAND_TYPES.FINISH_ADVENTURE_RUN]: ['runId'],
    [GAME_COMMAND_TYPES.CLAIM_QUICK_BATTLE]: ['mode'],
    [GAME_COMMAND_TYPES.PURCHASE_PACK]: ['productId', 'quantity', 'race'],
    [GAME_COMMAND_TYPES.PURCHASE_SUPPORT_PACK]: ['quantity'],
    [GAME_COMMAND_TYPES.USE_SUPPORT_ITEM]: ['itemId', 'targetCardId', 'race', 'count'],
    [GAME_COMMAND_TYPES.REDEEM_CARD_SELECTOR]: ['itemId', 'cardId'],
    [GAME_COMMAND_TYPES.ENHANCE_CARD]: ['cardId', 'targetEnhancement', 'materialCardIds', 'boosterId'],
    [GAME_COMMAND_TYPES.DISMANTLE_CARDS]: ['rarity'],
    [GAME_COMMAND_TYPES.DISMANTLE_SUPPORT_ITEM]: ['itemId', 'count'],
    [GAME_COMMAND_TYPES.SET_REPRESENTATIVE_CARD]: ['cardId'],
    [GAME_COMMAND_TYPES.SET_CARD_LOCK]: ['cardId', 'locked'],
    [GAME_COMMAND_TYPES.START_MINIGAME]: ['game', 'difficulty'],
    [GAME_COMMAND_TYPES.FINISH_MINIGAME]: ['runId', 'inputLog', 'score'],
    [GAME_COMMAND_TYPES.PLAY_LADDER]: ['lane'],
    [GAME_COMMAND_TYPES.BUY_LOTTO_TICKET]: ['numbers'],
    [GAME_COMMAND_TYPES.ATTACK_WORLD_BOSS]: ['eventId'],
    [GAME_COMMAND_TYPES.CLAIM_WORLD_BOSS_REWARD]: ['eventId'],
    // 길드(PDB-16). 인자가 없는 명령도 빈 배열로 반드시 선언해야 한다.
    [GAME_COMMAND_TYPES.CREATE_GUILD]: ['name', 'tag', 'emblem'],
    [GAME_COMMAND_TYPES.DISBAND_GUILD]: [],
    [GAME_COMMAND_TYPES.UPDATE_GUILD_SETTINGS]: ['notice', 'emblem', 'joinMode'],
    [GAME_COMMAND_TYPES.REQUEST_JOIN_GUILD]: ['guildId'],
    [GAME_COMMAND_TYPES.CANCEL_JOIN_REQUEST]: ['guildId'],
    [GAME_COMMAND_TYPES.RESOLVE_JOIN_REQUEST]: ['targetUserId', 'approve'],
    [GAME_COMMAND_TYPES.LEAVE_GUILD]: [],
    [GAME_COMMAND_TYPES.KICK_GUILD_MEMBER]: ['targetUserId'],
    [GAME_COMMAND_TYPES.SET_GUILD_MEMBER_ROLE]: ['targetUserId', 'role'],
    [GAME_COMMAND_TYPES.CLAIM_GUILD_WEEKLY_REWARD]: [],
    [GAME_COMMAND_TYPES.ATTACK_GUILD_RAID]: [],
    [GAME_COMMAND_TYPES.CLAIM_GUILD_RAID_REWARD]: [],
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
    case GAME_COMMAND_TYPES.SAVE_FORMATION_PRESET:
    case GAME_COMMAND_TYPES.APPLY_FORMATION_PRESET:
    case GAME_COMMAND_TYPES.DELETE_FORMATION_PRESET:
      // presetId 는 사용자가 붙이는 이름이자 저장 키다. 화면에는 이스케이프해서 그린다.
      validateString(issues, payload.presetId, 'payload.presetId', 12);
      if (type === GAME_COMMAND_TYPES.SAVE_FORMATION_PRESET) {
        if (!Array.isArray(payload.formation) || payload.formation.length !== 5) {
          addIssue(issues, 'payload.formation', '카드 ID 5개 배열 필요');
        } else {
          payload.formation.forEach((cardId, index) => validateString(issues, cardId, `payload.formation.${index}`, 80));
          if (new Set(payload.formation).size !== payload.formation.length) {
            addIssue(issues, 'payload.formation', '중복 카드 ID 불가');
          }
        }
      }
      break;
    case GAME_COMMAND_TYPES.CLAIM_ADVENTURE_REWARDS:
      if (payload.mode !== 'offline') addIssue(issues, 'payload.mode', 'offline required');
      break;
    case GAME_COMMAND_TYPES.START_ADVENTURE_RUN:
      if (payload.mode !== undefined && !['normal', 'hard', 'hell'].includes(payload.mode)) {
        addIssue(issues, 'payload.mode', 'normal, hard 또는 hell 필요');
      }
      break;
    case GAME_COMMAND_TYPES.CLAIM_QUICK_BATTLE:
      if (payload.mode !== undefined && !['normal', 'hard'].includes(payload.mode)) {
        addIssue(issues, 'payload.mode', 'normal 또는 hard 필요');
      }
      break;
    case GAME_COMMAND_TYPES.FINISH_ADVENTURE_RUN:
      validateString(issues, payload.runId, 'payload.runId', 100);
      break;
    case GAME_COMMAND_TYPES.PURCHASE_PACK:
      validateString(issues, payload.productId, 'payload.productId', 80);
      // 100개 묶음은 서버 RPC(gacha_s2_purchase_pack)도 함께 허용해야 한다. 한쪽만 넓히면 거절된다.
      if (![1, 10, 100].includes(payload.quantity)) addIssue(issues, 'payload.quantity', '1, 10 또는 100 필요');
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
    case GAME_COMMAND_TYPES.DISMANTLE_CARDS:
      if (!['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'].includes(payload.rarity)) {
        addIssue(issues, 'payload.rarity', 'F~SSS 등급 필요');
      }
      break;
    case GAME_COMMAND_TYPES.DISMANTLE_SUPPORT_ITEM:
      validateString(issues, payload.itemId, 'payload.itemId', 80);
      // 분해 가능 여부는 서버가 다시 판정한다. 여기서는 형식만 본다.
      // 상한은 실제 보유량을 감당해야 한다. 999 로 잡았다가 보유 1,000개 이상인
      // 유저(655명, 최대 22,947개)의 전량 분해가 전부 거부된 사고가 있었다.
      if (!Number.isInteger(payload.count) || payload.count < 1 || payload.count > SUPPORT_ITEM_DISMANTLE_MAX_COUNT) {
        addIssue(issues, 'payload.count', `1~${SUPPORT_ITEM_DISMANTLE_MAX_COUNT} 정수 필요`);
      }
      break;
    case GAME_COMMAND_TYPES.PURCHASE_SUPPORT_PACK:
      if (![1, 10].includes(payload.quantity)) addIssue(issues, 'payload.quantity', '1 or 10 required');
      break;
    case GAME_COMMAND_TYPES.USE_SUPPORT_ITEM: {
      validateString(issues, payload.itemId, 'payload.itemId', 80);
      const targetRequired = payload.itemId === 'cardExpPotion' || payload.itemId === 'cardExpPotionLarge';
      const raceRequired = payload.itemId === 'raceTicket';
      if (targetRequired) validateString(issues, payload.targetCardId, 'payload.targetCardId', 80);
      else if (payload.targetCardId !== null && payload.targetCardId !== undefined) addIssue(issues, 'payload.targetCardId', 'targetCardId is only valid for EXP potions');
      if (raceRequired && !['저그', '테란', '프로토스'].includes(payload.race)) addIssue(issues, 'payload.race', 'valid race required');
      else if (!raceRequired && payload.race !== null && payload.race !== undefined) addIssue(issues, 'payload.race', 'race is only valid for raceTicket');
      if (payload.count !== null && payload.count !== undefined) {
        if (!targetRequired) addIssue(issues, 'payload.count', 'count is only valid for EXP potions');
        else if (!Number.isInteger(payload.count) || payload.count < 1 || payload.count > 9999) addIssue(issues, 'payload.count', '1~9999 정수 필요');
      }
      break;
    }
    case GAME_COMMAND_TYPES.REDEEM_CARD_SELECTOR:
      if (!['ssCardSelector', 'sssCardSelector'].includes(payload.itemId)) {
        addIssue(issues, 'payload.itemId', 'SS 또는 SSS 카드 선택권 필요');
      }
      validateString(issues, payload.cardId, 'payload.cardId', 80);
      break;
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
        // memory: {index, atMs} (flip 단위). sumTen: {start, end, atMs} (드래그 범위).
        // 두 포맷 중 하나여야 한다 (서버 RPC 가 game 종류별로 알맞게 검증).
        const memoryAction = isNonNegativeInteger(action.index);
        const sumTenAction = isNonNegativeInteger(action.start) && isNonNegativeInteger(action.end);
        if (!memoryAction && !sumTenAction) {
          addIssue(issues, `payload.inputLog.${index}`, 'memory(index) 또는 sumTen(start/end) 액션 필요');
        }
      });
      if (!isNonNegativeInteger(payload.score)) addIssue(issues, 'payload.score', '0 이상 정수 필요');
      break;
    case GAME_COMMAND_TYPES.PLAY_LADDER:
      if (!isNonNegativeInteger(payload.lane) || payload.lane > 5) addIssue(issues, 'payload.lane', '0~5 출발점 필요');
      break;
    case GAME_COMMAND_TYPES.BUY_LOTTO_TICKET:
      if (!Array.isArray(payload.numbers) || payload.numbers.length !== 6) {
        addIssue(issues, 'payload.numbers', '번호 6개 배열 필요');
      } else {
        payload.numbers.forEach((value, index) => {
          if (!Number.isInteger(value) || value < 1 || value > 18) {
            addIssue(issues, `payload.numbers.${index}`, '1~18 정수 필요');
          }
        });
        if (new Set(payload.numbers).size !== payload.numbers.length) {
          addIssue(issues, 'payload.numbers', '중복 번호 불가');
        }
      }
      break;
    case GAME_COMMAND_TYPES.ATTACK_WORLD_BOSS:
      validateString(issues, payload.eventId, 'payload.eventId', 100);
      break;
    case GAME_COMMAND_TYPES.CLAIM_WORLD_BOSS_REWARD:
      validateString(issues, payload.eventId, 'payload.eventId', 100);
      break;
    case GAME_COMMAND_TYPES.CREATE_GUILD:
      validateString(issues, payload.name, 'payload.name', 20);
      if (payload.tag !== undefined && payload.tag !== null) validateString(issues, payload.tag, 'payload.tag', 6);
      if (payload.emblem !== undefined && payload.emblem !== null) validateString(issues, payload.emblem, 'payload.emblem', 32);
      break;
    case GAME_COMMAND_TYPES.UPDATE_GUILD_SETTINGS:
      if (payload.notice !== undefined && payload.notice !== null && typeof payload.notice !== 'string') {
        addIssue(issues, 'payload.notice', '문자열 필요');
      }
      if (payload.emblem !== undefined && payload.emblem !== null) validateString(issues, payload.emblem, 'payload.emblem', 32);
      if (payload.joinMode !== undefined && payload.joinMode !== null && !['approval', 'auto'].includes(payload.joinMode)) {
        addIssue(issues, 'payload.joinMode', 'approval 또는 auto 필요');
      }
      break;
    case GAME_COMMAND_TYPES.REQUEST_JOIN_GUILD:
    case GAME_COMMAND_TYPES.CANCEL_JOIN_REQUEST:
      validateString(issues, payload.guildId, 'payload.guildId', 64);
      break;
    case GAME_COMMAND_TYPES.RESOLVE_JOIN_REQUEST:
      validateString(issues, payload.targetUserId, 'payload.targetUserId', 64);
      if (typeof payload.approve !== 'boolean') addIssue(issues, 'payload.approve', 'boolean 필요');
      break;
    case GAME_COMMAND_TYPES.KICK_GUILD_MEMBER:
      validateString(issues, payload.targetUserId, 'payload.targetUserId', 64);
      break;
    case GAME_COMMAND_TYPES.SET_GUILD_MEMBER_ROLE:
      validateString(issues, payload.targetUserId, 'payload.targetUserId', 64);
      if (!['officer', 'member'].includes(payload.role)) addIssue(issues, 'payload.role', 'officer 또는 member 필요');
      break;
    // 추가 인자가 없는 길드 명령들.
    case GAME_COMMAND_TYPES.DISBAND_GUILD:
    case GAME_COMMAND_TYPES.LEAVE_GUILD:
    case GAME_COMMAND_TYPES.CLAIM_GUILD_WEEKLY_REWARD:
    case GAME_COMMAND_TYPES.ATTACK_GUILD_RAID:
    case GAME_COMMAND_TYPES.CLAIM_GUILD_RAID_REWARD:
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
