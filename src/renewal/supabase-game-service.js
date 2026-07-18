import {
  GAME_ERROR_CODES,
  createGameCommand,
  createGameError,
  validateGameResponse,
} from './service-contract.js';

export const SUPABASE_GAME_SERVICE_METHODS = Object.freeze([
  'loadSnapshot',
  'getWorldBossStatus',
  'getPowerRanking',
  'getBridgeStatus',
  'executeCommand',
  'sendCommand',
]);

function endpointFor(projectUrl) {
  return `${projectUrl.replace(/\/+$/, '')}/functions/v1/game-command`;
}

function defaultIdempotencyKey() {
  if (typeof globalThis.crypto?.randomUUID === 'function') return globalThis.crypto.randomUUID();
  throw new Error('Secure UUID generator is unavailable.');
}

export function createSupabaseGameService(options = {}) {
  const projectUrl = String(options.projectUrl ?? '').trim();
  const publishableKey = String(options.publishableKey ?? '').trim();
  const getAccessToken = options.getAccessToken;
  const fetchImpl = options.fetch ?? globalThis.fetch;
  const clock = options.clock ?? { now: () => Date.now() };
  const createIdempotencyKey = options.createIdempotencyKey ?? defaultIdempotencyKey;
  if (!/^https:\/\/[^/]+$/.test(projectUrl)) throw new Error('Valid Supabase project URL is required.');
  if (!publishableKey) throw new Error('Supabase publishable key is required.');
  if (typeof getAccessToken !== 'function') throw new Error('Supabase access-token provider is required.');
  if (typeof fetchImpl !== 'function') throw new Error('Fetch implementation is required.');

  async function request(body) {
    const accessToken = await getAccessToken();
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
    const response = await request({ kind: 'snapshot' });
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
    const response = await request({ kind: 'worldBossStatus', eventId });
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
    const response = await request({ kind: 'bridgeStatus' });
    if (response.ok === false) return response;
    return response.status ?? { canUseDonationBridge: false, soopId: null };
  }

  const service = {
    loadSnapshot,
    getWorldBossStatus,
    getPowerRanking,
    getBridgeStatus,
    executeCommand,
    sendCommand,
  };
  SUPABASE_GAME_SERVICE_METHODS.forEach((method) => {
    if (typeof service[method] !== 'function') throw new Error(`Supabase game service missing method: ${method}`);
  });
  return service;
}
