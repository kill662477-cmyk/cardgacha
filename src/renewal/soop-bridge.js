const SDK_URLS = [
  'https://static.sooplive.com/asset/app/sooplive-chat-sdk.js',
  'https://static.sooplive.com/asset/app/sooplive-chat-sdk.min.js',
  'https://static.sooplive.com/asset/app/chat-sdk/sooplive-chat-sdk.js',
  'https://static.sooplive.com/asset/app/chat-sdk/sooplive-chat-sdk.min.js',
  'https://static.sooplive.com/asset/app/chat-sdk/latest/chat-sdk.min.js',
  'https://static.sooplive.com/asset/app/chat-sdk/chat-sdk.min.js',
];
const DONATION_ACTIONS = new Set(['BALLOON_GIFTED', 'BATTLE_MISSION_GIFTED']);
const DEFAULT_ACCESS_TOKEN_TTL_MS = 2 * 60 * 60 * 1000;
const ACCESS_TOKEN_REFRESH_EARLY_MS = 10 * 60 * 1000;
const config = globalThis.__CARD_GACHA_CONFIG__ ?? {};
const endpoint = `${String(config.supabaseUrl ?? '').replace(/\/+$/, '')}/functions/v1/soop-bridge`;
const publishableKey = String(config.supabasePublishableKey ?? '');
const elements = Object.fromEntries([
  'bridgeState', 'bridgeAuthForm', 'bridgeKey', 'soopAuthButton', 'collectButton', 'stopButton',
  'bridgeNotice', 'eventCount', 'pointCount', 'skipCount', 'eventLog',
].map((id) => [id, document.getElementById(id)]));
const state = {
  session: sessionStorage.getItem('gachaS2BridgeSession') ?? '',
  soopId: sessionStorage.getItem('gachaS2BridgeSoopId') ?? '',
  credentials: null,
  sdk: null,
  connected: false,
  events: 0,
  points: 0,
  skipped: 0,
};

function notice(message, kind = '') {
  elements.bridgeNotice.textContent = message;
  elements.bridgeNotice.dataset.kind = kind;
}

function render() {
  const ready = Boolean(state.session);
  elements.bridgeState.textContent = state.connected ? 'COLLECTING' : ready ? 'READY' : 'OFFLINE';
  elements.bridgeState.dataset.state = state.connected ? 'collecting' : ready ? 'ready' : 'offline';
  elements.soopAuthButton.disabled = !ready || state.connected;
  elements.collectButton.disabled = !state.credentials || state.connected;
  elements.stopButton.disabled = !state.connected;
  elements.eventCount.textContent = String(state.events);
  elements.pointCount.textContent = `${state.points.toLocaleString('ko-KR')} P`;
  elements.skipCount.textContent = String(state.skipped);
}

async function request(action, payload = {}) {
  if (!endpoint.startsWith('https://') || !publishableKey) throw new Error('서버 연결 설정이 필요합니다.');
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      apikey: publishableKey,
      'Content-Type': 'application/json',
      ...(state.session ? { Authorization: `Bridge ${state.session}` } : {}),
    },
    body: JSON.stringify({ action, ...payload }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || data.ok === false) throw new Error(data.error ?? '요청 처리 실패');
  return data;
}

function logEvent(label, amount, kind = '') {
  const article = document.createElement('article');
  article.dataset.kind = kind;
  const time = document.createElement('time');
  const text = document.createElement('span');
  const value = document.createElement('b');
  time.textContent = new Date().toLocaleTimeString('ko-KR', { hour12: false });
  text.textContent = label;
  value.textContent = amount;
  article.append(time, text, value);
  elements.eventLog.prepend(article);
}

function first(message, keys) {
  for (const key of keys) {
    const value = key.split('.').reduce((item, part) => item?.[part], message);
    if (value !== undefined && value !== null && String(value).trim()) return String(value).trim();
  }
  return '';
}

function giftAmount(message) {
  return Math.floor(Number(first(message, ['count', 'giftCount', 'balloonCount', 'amount', 'cnt', 'starballoonCount', 'starBalloonCount', 'data.count', 'data.giftCount', 'data.amount'])) || 0);
}
function sender(message) {
  return first(message, ['userId', 'senderId', 'fromUserId', 'fanId', 'donorId', 'user.id', 'sender.id', 'data.userId', 'data.senderId']);
}
function recipient(message) {
  return first(message, ['bjId', 'receiverId', 'broadId', 'streamerId', 'ownerId', 'data.bjId', 'data.receiverId']);
}
function nickname(message) {
  return first(message, ['userNickname', 'userNickName', 'userNick', 'nickname', 'nickName', 'senderNickname', 'senderNickName', 'fromNickname', 'fanNickname', 'data.userNickname', 'data.nickname']) || sender(message) || '알 수 없음';
}

async function eventId(action, message, senderSoopId, recipientSoopId, amount) {
  const upstream = first(message, ['eventId', 'giftId', 'transactionId', 'donationId', 'id', 'data.eventId', 'data.giftId', 'data.transactionId']);
  if (upstream) return `soop:${action}:${upstream}`;
  const receivedAt = first(message, ['createdAt', 'timestamp', 'time', 'data.createdAt', 'data.timestamp'])
    || `recv:${Date.now()}:${crypto.randomUUID()}`;
  const source = JSON.stringify({ action, senderSoopId, recipientSoopId, amount, receivedAt, message });
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(source)));
  return `soop:${[...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('')}`;
}

async function handleMessage(action, message) {
  if (!DONATION_ACTIONS.has(action)) return;
  const senderSoopId = sender(message);
  const recipientSoopId = recipient(message) || state.credentials?.soopId;
  const amount = giftAmount(message);
  const name = nickname(message);
  if (!senderSoopId || !recipientSoopId || amount < 1) {
    state.skipped += 1;
    logEvent(`${name} · 식별 정보 부족`, '제외', 'skip');
    return render();
  }
  try {
    const result = await request('donation', {
      eventId: await eventId(action, message, senderSoopId, recipientSoopId, amount),
      eventAction: action,
      senderSoopId,
      recipientSoopId,
      amount,
    });
    if (result.applied) {
      state.events += 1;
      state.points += result.pointsPerAccount;
      logEvent(`${action === 'BATTLE_MISSION_GIFTED' ? '대결미션 · ' : ''}${name} → ${recipientSoopId}`, `+${result.pointsPerAccount}P`);
    } else {
      state.skipped += 1;
      logEvent(`${name} · 중복 이벤트`, '중복', 'skip');
    }
  } catch (error) {
    state.skipped += 1;
    logEvent(`${name} · ${error.message}`, '실패', 'error');
  }
  render();
}

function loadScript(url) {
  return new Promise((resolve, reject) => {
    if ([...document.scripts].some((script) => script.src === url)) return resolve();
    const script = document.createElement('script');
    script.src = url;
    script.async = true;
    script.onload = resolve;
    script.onerror = reject;
    document.head.append(script);
  });
}

async function chatSdk() {
  if (window.SOOP?.ChatSDK) return window.SOOP.ChatSDK;
  if (window.ChatSDK) return window.ChatSDK;
  let lastError;
  for (const url of SDK_URLS) {
    try {
      await loadScript(url);
      if (window.SOOP?.ChatSDK) return window.SOOP.ChatSDK;
      if (window.ChatSDK) return window.ChatSDK;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? new Error('SOOP ChatSDK를 불러오지 못했습니다.');
}

let reconnectAttempts = 0;
let shouldStayConnected = false;
let reconnectTimer = null;
let tokenRefreshTimer = null;
let refreshPromise = null;
let manualStop = false;
let connectionSequence = 0;

function updateBridgeSession(session) {
  if (!session || typeof session !== 'string') return;
  state.session = session;
  sessionStorage.setItem('gachaS2BridgeSession', session);
}

function clearTokenRefreshTimer() {
  if (!tokenRefreshTimer) return;
  clearTimeout(tokenRefreshTimer);
  tokenRefreshTimer = null;
}

function tokenRefreshDelay(credentials = state.credentials) {
  const expiresAt = Number(credentials?.accessTokenExpiresAt);
  const fallback = Date.now() + DEFAULT_ACCESS_TOKEN_TTL_MS;
  const target = Number.isFinite(expiresAt) && expiresAt > Date.now() ? expiresAt : fallback;
  return Math.max(60_000, target - Date.now() - ACCESS_TOKEN_REFRESH_EARLY_MS);
}

function scheduleTokenRefresh() {
  clearTokenRefreshTimer();
  if (!state.connected || !state.credentials || manualStop) return;
  tokenRefreshTimer = setTimeout(() => {
    tokenRefreshTimer = null;
    void refreshActiveConnection();
  }, tokenRefreshDelay());
}

function setCredentials(credentials) {
  if (!credentials?.accessToken || !credentials?.clientId || !credentials?.soopId) throw new Error('SOOP 인증 정보가 올바르지 않습니다.');
  state.credentials = {
    ...credentials,
    accessTokenExpiresAt: Number(credentials.accessTokenExpiresAt) || Date.now() + DEFAULT_ACCESS_TOKEN_TTL_MS,
  };
}

function invalidateConnection() {
  connectionSequence += 1;
  try { state.sdk?.disconnect?.(); } catch {}
}

function isTokenError(code, message) {
  return /(?:401|auth|token|expire|unauthori[sz]ed)/i.test(`${code ?? ''} ${message ?? ''}`);
}

async function refreshCredentials() {
  if (refreshPromise) return refreshPromise;
  refreshPromise = request('refreshToken')
    .then((result) => {
      updateBridgeSession(result.session);
      setCredentials(result.credentials);
      return result.credentials;
    })
    .finally(() => { refreshPromise = null; });
  return refreshPromise;
}

async function connect() {
  manualStop = false;
  const connectionId = ++connectionSequence;
  try {
    notice('SOOP ChatSDK 연결 중');
    const ChatSDK = await chatSdk();
    try { state.sdk = new ChatSDK(state.credentials.clientId); } catch { state.sdk = new ChatSDK(state.credentials.clientId, ''); }
    state.sdk.init?.();
    state.sdk.handleMessageReceived((action, message) => { void handleMessage(action, message); });
    state.sdk.handleChatClosed(() => {
      if (connectionId !== connectionSequence) return;
      state.connected = false;
      clearTokenRefreshTimer();
      render();
      if (manualStop) { manualStop = false; return; }
      notice('SOOP 연결 끊김 · 자동 재연결 시도 중', 'error');
      scheduleReconnect();
    });
    state.sdk.handleError((code, message) => {
      if (connectionId !== connectionSequence) return;
      notice(`SOOP 오류: ${code || message || 'unknown'}`, 'error');
      if (isTokenError(code, message)) {
        state.connected = false;
        clearTokenRefreshTimer();
        render();
        scheduleReconnect();
      }
    });
    state.sdk.setAuth(state.credentials.accessToken);
    await state.sdk.connect();
    if (connectionId !== connectionSequence) return false;
    state.connected = true;
    shouldStayConnected = true;
    reconnectAttempts = 0;
    render();
    scheduleTokenRefresh();
    notice(`수집 중 · ${state.credentials.soopId}`, 'ok');
    return true;
  } catch (error) {
    if (connectionId !== connectionSequence) return false;
    state.connected = false;
    clearTokenRefreshTimer();
    render();
    notice(error.message, 'error');
    return false;
  }
}

function scheduleReconnect() {
  if (reconnectTimer || manualStop) return;
  reconnectAttempts += 1;
  // 방송 오버레이는 자가복구되어야 하므로 영구 포기하지 않고 30초 상한 백오프로 계속 재시도한다.
  const delayMs = Math.min(30_000, 3_000 * reconnectAttempts);
  notice(`SOOP 재연결 대기 중 (${reconnectAttempts}회)`, '');
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    void reconnectWithFreshToken();
  }, delayMs);
}

function accessTokenNearExpiry() {
  const expiresAt = Number(state.credentials?.accessTokenExpiresAt);
  return !Number.isFinite(expiresAt) || expiresAt - Date.now() <= ACCESS_TOKEN_REFRESH_EARLY_MS;
}

async function reconnectWithFreshToken() {
  try {
    invalidateConnection();
    // 단순 채팅 끊김에는 기존 토큰으로 재연결한다. refresh 엔드포인트 장애가 재연결을
    // 막지 않도록, 자격이 없거나 만료가 임박할 때만 토큰을 새로 받는다.
    if (!state.credentials || accessTokenNearExpiry()) await refreshCredentials();
    if (!await connect()) scheduleReconnect();
  } catch (error) {
    // 토큰 갱신이 실패해도 기존 자격이 남아 있으면 그대로 재연결을 시도한다.
    if (state.credentials) {
      try { if (await connect()) return; } catch { /* fall through to backoff */ }
    }
    notice(`SOOP 재연결 실패 · ${error.message}`, 'error');
    scheduleReconnect();
  }
}

async function refreshActiveConnection() {
  if (!state.connected || manualStop) return;
  invalidateConnection();
  state.connected = false;
  render();
  try {
    await refreshCredentials();
    if (!await connect()) scheduleReconnect();
  } catch (error) {
    notice(`SOOP 토큰 갱신 실패 · ${error.message}`, 'error');
    scheduleReconnect();
  }
}

function disconnect() {
  manualStop = true;
  shouldStayConnected = false;
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
  clearTokenRefreshTimer();
  reconnectAttempts = 0;
  invalidateConnection();
  state.connected = false;
  render();
  notice('수집 중지됨');
}

elements.bridgeAuthForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    const result = await request('authenticate', { key: elements.bridgeKey.value });
    elements.bridgeKey.value = '';
    updateBridgeSession(result.session);
    state.soopId = result.soopId;
    sessionStorage.setItem('gachaS2BridgeSoopId', state.soopId);
    notice(`방송인 인증 완료 · ${state.soopId}`, 'ok');
    render();
  } catch (error) {
    notice(error.message, 'error');
  }
});

elements.soopAuthButton.addEventListener('click', async () => {
  try {
    const result = await request('soopStart');
    location.href = result.authorizeUrl;
  } catch (error) {
    notice(error.message, 'error');
  }
});
elements.collectButton.addEventListener('click', () => { void connect(); });
elements.stopButton.addEventListener('click', disconnect);

// OBS 브라우저 소스/백그라운드 탭은 웹소켓·타이머가 정지돼 연결이 끊기고 백오프 타이머도
// 지연된다. 탭이 다시 보이거나 네트워크가 복구되면 즉시 재연결을 시도해 방치 시간을 없앤다.
function wakeReconnect() {
  if (manualStop || !shouldStayConnected || state.connected) return;
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
  reconnectAttempts = 0;
  void reconnectWithFreshToken();
}
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') wakeReconnect();
});
window.addEventListener('online', wakeReconnect);

async function consumeCallback() {
  const fragment = new URLSearchParams(location.hash.slice(1));
  history.replaceState(null, '', location.pathname);
  if (fragment.has('error')) {
    const errors = { auth: '브리지 인증이 만료되었습니다.', mismatch: '브리지 KEY와 SOOP 계정이 일치하지 않습니다.', soop: 'SOOP 인증 처리 실패' };
    notice(errors[fragment.get('error')] ?? 'SOOP 인증 실패', 'error');
    return;
  }
  const exchange = fragment.get('exchange');
  if (!exchange) return;
  try {
    const result = await request('exchange', { exchange });
    setCredentials(result.credentials);
    notice(`SOOP 연결 완료 · ${state.credentials.soopId}`, 'ok');
  } catch (error) {
    notice(error.message, 'error');
  }
}

if (state.session) notice(`방송인 인증 유지 중 · ${state.soopId}`, 'ok');
render();
async function restoreCredentials() {
  if (!state.session || state.credentials) return;
  try {
    await refreshCredentials();
    notice(`SOOP connection restored · ${state.credentials.soopId}`, 'ok');
  } catch {
    // The session can legitimately expire while this tab is closed. The user
    // can authenticate again without exposing any stored SOOP token.
  }
}

void consumeCallback().then(restoreCredentials).finally(render);
