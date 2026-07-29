import {
  GAME_ERROR_CODES,
  createGameCommand,
  createGameError,
  validateGameResponse,
} from './service-contract.js';

export const SUPABASE_GAME_SERVICE_METHODS = Object.freeze([
  'loadSnapshot',
  'getWorldBossStatus',
  'getLottoState',
  'getGuildApplicantProfile',
  'getGuildMemberProfile',
  'getPowerRanking',
  'getBridgeStatus',
  'getMailbox',
  'markMailboxRead',
  'executeCommand',
  'sendCommand',
]);

function endpointFor(projectUrl) {
  return `${projectUrl.replace(/\/+$/, '')}/functions/v1/game-command`;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function defaultIdempotencyKey() {
  if (typeof globalThis.crypto?.randomUUID === 'function') return globalThis.crypto.randomUUID();
  throw new Error('Secure UUID generator is unavailable.');
}

export function createSupabaseGameService(options = {}) {
  const projectUrl = String(options.projectUrl ?? '').trim();
  const publishableKey = String(options.publishableKey ?? '').trim();
  const getAccessToken = options.getAccessToken;
  const fetchImpl = options.fetch ?? globalThis.fetch;
  const readRpc = typeof options.readRpc === 'function' ? options.readRpc : null;
  const clock = options.clock ?? { now: () => Date.now() };
  const createIdempotencyKey = options.createIdempotencyKey ?? defaultIdempotencyKey;
  if (!/^https:\/\/[^/]+$/.test(projectUrl)) throw new Error('Valid Supabase project URL is required.');
  if (!publishableKey) throw new Error('Supabase publishable key is required.');
  if (typeof getAccessToken !== 'function') throw new Error('Supabase access-token provider is required.');
  if (typeof fetchImpl !== 'function') throw new Error('Fetch implementation is required.');

  async function request(body) {
    let accessToken;
    try {
      accessToken = await getAccessToken();
    } catch (error) {
      return createGameError({
        code: GAME_ERROR_CODES.OFFLINE,
        message: '로그인 세션을 확인하지 못했습니다.',
        serverTime: clock.now(),
        details: { message: error?.message ?? String(error) },
      });
    }
    if (typeof accessToken !== 'string' || !accessToken) {
      return createGameError({
        code: GAME_ERROR_CODES.AUTH_REQUIRED,
        message: '로그인이 필요합니다.',
        serverTime: clock.now(),
      });
    }
    let response;
    try {
      response = await fetchImpl(endpointFor(projectUrl), {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          apikey: publishableKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });
    } catch (error) {
      return createGameError({
        code: GAME_ERROR_CODES.OFFLINE,
        message: '게임 서버에 연결할 수 없습니다.',
        serverTime: clock.now(),
        details: { message: error?.message ?? String(error) },
      });
    }
    let payload;
    try {
      payload = await response.json();
    } catch {
      payload = null;
    }
    if (payload?.ok === false) {
      if (payload.contractVersion === 1) return payload;
      const code = Object.values(GAME_ERROR_CODES).includes(payload.code)
        ? payload.code
        : GAME_ERROR_CODES.INTERNAL_ERROR;
      return createGameError({
        code,
        message: typeof payload.message === 'string' ? payload.message : '게임 서버 요청에 실패했습니다.',
        serverTime: Number.isSafeInteger(payload.serverTime) ? payload.serverTime : clock.now(),
      });
    }
    if (!response.ok || !payload) {
      return createGameError({
        code: response.status === 401 ? GAME_ERROR_CODES.AUTH_REQUIRED
          : response.status === 429 ? GAME_ERROR_CODES.RATE_LIMITED
            : GAME_ERROR_CODES.INTERNAL_ERROR,
        message: response.status === 401 ? '로그인 세션이 만료되었습니다.' : '게임 서버 응답이 올바르지 않습니다.',
        serverTime: clock.now(),
        details: { status: response.status },
      });
    }
    return payload;
  }

  async function readRequest(edgeBody, rpcName, rpcArgs = {}) {
    if (!readRpc) return request(edgeBody);
    let response;
    try {
      response = await readRpc(rpcName, rpcArgs);
    } catch (error) {
      return createGameError({
        code: GAME_ERROR_CODES.OFFLINE,
        message: '조회 서버에 연결할 수 없습니다.',
        serverTime: clock.now(),
        details: { message: error?.message ?? String(error) },
      });
    }
    if (response?.error) {
      const status = Number(response.error.status ?? response.status ?? 0);
      return createGameError({
        code: status === 401 || status === 403
          ? GAME_ERROR_CODES.AUTH_REQUIRED
          : GAME_ERROR_CODES.INTERNAL_ERROR,
        message: status === 401 || status === 403
          ? '로그인이 필요합니다.'
          : '조회 요청을 처리하지 못했습니다.',
        serverTime: clock.now(),
        details: { status, code: response.error.code ?? null },
      });
    }
    if (!response || !response.data || typeof response.data !== 'object') {
      return createGameError({
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '조회 서버 응답이 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    return response.data;
  }

  async function executeCommand(command) {
    const response = await request({ kind: 'command', command });
    const validation = validateGameResponse(response);
    if (!validation.valid
      || (response.commandId !== null && response.commandId !== command.commandId)
      || (response.idempotencyKey !== null && response.idempotencyKey !== command.idempotencyKey)) {
      return createGameError({
        command,
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '게임 서버 응답 계약이 일치하지 않습니다.',
        serverTime: clock.now(),
        details: { issues: validation.issues, responseCommandId: response.commandId ?? null },
      });
    }
    return response;
  }

  function sendCommand(type, payload, expectedRevision, idempotencyKey = createIdempotencyKey()) {
    return executeCommand(createGameCommand({
      type,
      payload,
      expectedRevision,
      idempotencyKey,
      clientSentAt: clock.now(),
    }));
  }

  async function loadSnapshot() {
    const response = await readRequest(
      { kind: 'snapshot' },
      'gacha_s2_client_get_snapshot',
    );
    if (response.ok === false) return response;
    if (!response.snapshot || typeof response.snapshot !== 'object'
      || !Number.isSafeInteger(response.snapshot.revision) || response.snapshot.revision < 0) {
      return createGameError({
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '계정 상태 응답이 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    return response;
  }

  async function getWorldBossStatus(eventId = null) {
    const response = await readRequest(
      { kind: 'worldBossStatus', eventId },
      'gacha_s2_client_get_world_boss_status',
      { p_event_id: eventId },
    );
    if (response.ok === false) return response;
    if (!response.status || typeof response.status !== 'object') {
      return createGameError({
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '월드보스 상태 응답이 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    return response;
  }

  // 길드 상태(PDB-16). 스냅샷을 건드리지 않고 월드보스 상태와 같은 방식으로 분리 조회한다.
  async function getGuildState(guildId = null) {
    const response = await readRequest(
      { kind: 'guildState', guildId },
      'gacha_s2_client_get_guild_state',
      { p_guild_id: guildId },
    );
    if (response.ok === false) return response;
    if (!response.state || typeof response.state !== 'object') {
      return createGameError({
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '길드 정보 응답이 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    return response.state;
  }

  async function getLottoState() {
    const response = await readRequest(
      { kind: 'lottoState' },
      'gacha_s2_client_get_lotto_state',
    );
    if (response.ok === false) return response;
    if (!response.state || typeof response.state !== 'object') {
      return createGameError({
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '로또 정보를 불러오지 못했습니다.',
        serverTime: clock.now(),
      });
    }
    return response.state;
  }

  async function getGuildApplicantProfile(targetUserId) {
    if (typeof targetUserId !== 'string' || !UUID_PATTERN.test(targetUserId)) {
      return createGameError({
        code: GAME_ERROR_CODES.VALIDATION_FAILED,
        message: '신청자 정보가 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    const response = await request({ kind: 'guildApplicantProfile', targetUserId });
    if (response.ok === false) return response;
    if (!response.profile || typeof response.profile !== 'object') {
      return createGameError({
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '신청자 정보 응답이 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    return response.profile;
  }

  async function getGuildMemberProfile(targetUserId) {
    if (typeof targetUserId !== 'string' || !UUID_PATTERN.test(targetUserId)) {
      return createGameError({
        code: GAME_ERROR_CODES.VALIDATION_FAILED,
        message: '길드원 정보가 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    const response = await request({ kind: 'guildMemberProfile', targetUserId });
    if (response.ok === false) return response;
    if (!response.profile || typeof response.profile !== 'object') {
      return createGameError({
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '길드원 정보 응답이 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    return response.profile;
  }

  async function getGuildRaidStatus() {
    const response = await readRequest(
      { kind: 'guildRaidStatus' },
      'gacha_s2_client_get_guild_raid_status',
    );
    if (response.ok === false) return response;
    return response.status ?? { active: false, raid: null };
  }

  async function getPowerRanking() {
    const response = await request({ kind: 'powerRanking' });
    if (response.ok === false) return response;
    if (!response.ranking || typeof response.ranking !== 'object') {
      return createGameError({
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '전투력 랭킹 응답이 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    return response.ranking;
  }

  async function getBridgeStatus() {
    const response = await readRequest(
      { kind: 'bridgeStatus' },
      'gacha_s2_client_get_bridge_status',
    );
    if (response.ok === false) return response;
    return response.status ?? { canUseDonationBridge: false, soopId: null };
  }

  async function getMailbox() {
    const response = await readRequest(
      { kind: 'mailbox' },
      'gacha_s2_client_get_mailbox',
      { p_limit: 50 },
    );
    if (response.ok === false) return response;
    if (!response.mailbox || typeof response.mailbox !== 'object') {
      return createGameError({
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '우편함 응답이 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    return response.mailbox;
  }

  async function markMailboxRead(mailId) {
    if (typeof mailId !== 'string' || !UUID_PATTERN.test(mailId)) {
      return createGameError({
        code: GAME_ERROR_CODES.VALIDATION_FAILED,
        message: '우편 정보가 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    const response = await request({ kind: 'mailboxRead', mailId });
    if (response.ok === false) return response;
    if (!response.result || typeof response.result !== 'object') {
      return createGameError({
        code: GAME_ERROR_CODES.INTERNAL_ERROR,
        message: '우편 읽음 처리 응답이 올바르지 않습니다.',
        serverTime: clock.now(),
      });
    }
    return response.result;
  }

  const service = {
    loadSnapshot,
    getWorldBossStatus,
    getLottoState,
    getGuildState,
    getGuildApplicantProfile,
    getGuildMemberProfile,
    getGuildRaidStatus,
    getPowerRanking,
    getBridgeStatus,
    getMailbox,
    markMailboxRead,
    executeCommand,
    sendCommand,
  };
  SUPABASE_GAME_SERVICE_METHODS.forEach((method) => {
    if (typeof service[method] !== 'function') throw new Error(`Supabase game service missing method: ${method}`);
  });
  return service;
}
