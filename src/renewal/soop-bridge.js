const SDK_URLS = [
  'https://static.sooplive.com/asset/app/sooplive-chat-sdk.js',
  'https://static.sooplive.com/asset/app/sooplive-chat-sdk.min.js',
  'https://static.sooplive.com/asset/app/chat-sdk/sooplive-chat-sdk.js',
  'https://static.sooplive.com/asset/app/chat-sdk/sooplive-chat-sdk.min.js',
  'https://static.sooplive.com/asset/app/chat-sdk/latest/chat-sdk.min.js',
  'https://static.sooplive.com/asset/app/chat-sdk/chat-sdk.min.js',
];
const DONATION_ACTIONS = new Set(['BALLOON_GIFTED', 'BATTLE_MISSION_GIFTED']);
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

const MAX_RECONNECT_ATTEMPTS = 4;
let reconnectAttempts = 0;
let reconnectTimer = null;
let manualStop = false;

async function connect() {
  try {
    notice('SOOP ChatSDK 연결 중');
    const ChatSDK = await chatSdk();
    try { state.sdk = new ChatSDK(state.credentials.clientId); } catch { state.sdk = new ChatSDK(state.credentials.clientId, ''); }
    state.sdk.init?.();
    state.sdk.handleMessageReceived((action, message) => { void handleMessage(action, message); });
    state.sdk.handleChatClosed(() => {
      state.connected = false;
      render();
      if (manualStop) { manualStop = false; return; }
      notice('SOOP 연결 끊김 · 자동 재연결 시도 중', 'error');
      scheduleReconnect();
    });
    state.sdk.handleError((code, message) => notice(`SOOP 오류: ${code || message || 'unknown'}`, 'error'));
    state.sdk.setAuth(state.credentials.accessToken);
    await state.sdk.connect();
    state.connected = true;
    reconnectAttempts = 0;
    render();
    notice(`수집 중 · ${state.credentials.soopId}`, 'ok');
  } catch (error) {
    state.connected = false;
    render();
    notice(error.message, 'error');
  }
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
    notice('SOOP 자동 재연결 실패 · 다시 연동해주세요', 'error');
    return;
  }
  reconnectAttempts += 1;
  const delayMs = Math.min(30_000, 3_000 * reconnectAttempts);
  notice(`SOOP 재연결 대기 중 (${reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS})`, '');
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    void reconnectWithFreshToken();
  }, delayMs);
}

async function reconnectWithFreshToken() {
  try {
    const result = await request('refreshToken');
    state.credentials = result.credentials;
    await connect();
  } catch (error) {
    notice(`SOOP 재연결 실패 · ${error.message}`, 'error');
    scheduleReconnect();
  }
}

function disconnect() {
  manualStop = true;
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
  reconnectAttempts = 0;
  try { state.sdk?.disconnect?.(); } catch {}
  state.connected = false;
  render();
  notice('수집 중지됨');
}

elements.bridgeAuthForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    const result = await request('authenticate', { key: elements.bridgeKey.value });
    elements.bridgeKey.value = '';
    state.session = result.session;
    state.soopId = result.soopId;
    sessionStorage.setItem('gachaS2BridgeSession', state.session);
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
    state.credentials = result.credentials;
    notice(`SOOP 연결 완료 · ${state.credentials.soopId}`, 'ok');
  } catch (error) {
    notice(error.message, 'error');
  }
}

if (state.session) notice(`방송인 인증 유지 중 · ${state.soopId}`, 'ok');
render();
void consumeCallback().finally(render);
