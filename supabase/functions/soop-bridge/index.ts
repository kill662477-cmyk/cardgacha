import { createClient } from '@supabase/supabase-js';

const AUTH_URL = 'https://openapi.sooplive.com/auth/code';
const TOKEN_URL = 'https://openapi.sooplive.com/auth/token';
const STATION_URL = 'https://openapi.sooplive.com/user/stationinfo';
const MAX_BODY_BYTES = 32 * 1024;
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function requiredEnv(name: string) {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`MISSING_ENV:${name}`);
  return value;
}

function adminClient() {
  return createClient(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function allowedOrigins() {
  return new Set((Deno.env.get('GAME_ALLOWED_ORIGINS') ?? '')
    .split(',').map((value) => value.trim()).filter(Boolean));
}

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin');
  if (!origin || !allowedOrigins().has(origin)) return { Vary: 'Origin' };
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function json(req: Request, body: unknown, status = 200) {
  return Response.json(body, { status, headers: { ...corsHeaders(req), 'Cache-Control': 'no-store' } });
}

function base64Url(bytes: Uint8Array) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function fromBase64Url(value: string) {
  const normalized = value.replaceAll('-', '+').replaceAll('_', '/').padEnd(Math.ceil(value.length / 4) * 4, '=');
  const binary = atob(normalized);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function hmac(value: string, secretName: string) {
  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(requiredEnv(secretName)), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(value)));
}

async function signedToken(payload: Record<string, unknown>) {
  const encoded = base64Url(encoder.encode(JSON.stringify(payload)));
  return `${encoded}.${base64Url(await hmac(encoded, 'SOOP_BRIDGE_SESSION_SECRET'))}`;
}

async function verifyToken(token: string, expectedType: string) {
  const [encoded, signature, extra] = token.split('.');
  if (!encoded || !signature || extra) return null;
  const expected = await hmac(encoded, 'SOOP_BRIDGE_SESSION_SECRET');
  const received = fromBase64Url(signature);
  if (received.length !== expected.length) return null;
  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) difference |= expected[index] ^ received[index];
  if (difference !== 0) return null;
  try {
    const payload = JSON.parse(decoder.decode(fromBase64Url(encoded)));
    if (payload.type !== expectedType || !Number.isSafeInteger(payload.exp) || payload.exp <= Date.now()) return null;
    return payload;
  } catch {
    return null;
  }
}

async function sha256Hex(value: string) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value)));
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function randomToken(byteLength = 32) {
  return base64Url(crypto.getRandomValues(new Uint8Array(byteLength)));
}

async function rateKey(req: Request) {
  const ip = (req.headers.get('cf-connecting-ip') ?? req.headers.get('x-forwarded-for')?.split(',')[0] ?? 'unknown').trim();
  return [...await hmac(ip, 'SOOP_BRIDGE_RATE_LIMIT_PEPPER')]
    .map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function bridgeToken(req: Request) {
  const match = req.headers.get('authorization')?.match(/^Bridge\s+(.+)$/i);
  return match?.[1] ?? '';
}

async function readBody(req: Request) {
  const contentLength = Number(req.headers.get('content-length') ?? 0);
  if (contentLength > MAX_BODY_BYTES) throw new Error('BODY_TOO_LARGE');
  const text = await req.text();
  if (encoder.encode(text).byteLength > MAX_BODY_BYTES) throw new Error('BODY_TOO_LARGE');
  return JSON.parse(text || '{}') as Record<string, unknown>;
}

function safeText(value: unknown, max: number) {
  const text = String(value ?? '').trim();
  return text && text.length <= max ? text : '';
}

function extractSoopLoginId(profileImageUrl: unknown) {
  if (typeof profileImageUrl !== 'string') return null;
  try {
    const url = new URL(profileImageUrl.trim());
    if (!/(^|\.)sooplive\.com$/i.test(url.hostname)) return null;
    const match = url.pathname.match(/\/LOGO\/([^/]+)\/([^/]+)\/([^/]+)\.[a-zA-Z0-9]+$/);
    if (!match || match[2] !== match[3] || match[1].toLowerCase() !== match[2].slice(0, 2).toLowerCase()) return null;
    return match[2];
  } catch {
    return null;
  }
}

function parseTokenPayload(payload: Record<string, unknown>, fallbackRefreshToken = '') {
  if (!payload?.access_token) throw new Error('TOKEN_EMPTY');
  return {
    accessToken: String(payload.access_token),
    // SOOP may not rotate the refresh_token on every refresh; keep the prior one if omitted.
    refreshToken: payload.refresh_token ? String(payload.refresh_token) : fallbackRefreshToken,
  };
}

async function exchangeSoopToken(code: string) {
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: requiredEnv('SOOP_DONATION_CLIENT_ID'),
    client_secret: requiredEnv('SOOP_DONATION_CLIENT_SECRET'),
    redirect_uri: requiredEnv('SOOP_DONATION_REDIRECT_URI'),
    code,
  });
  const response = await fetch(TOKEN_URL, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body,
  });
  if (!response.ok) throw new Error(`TOKEN_EXCHANGE_FAILED:${response.status}`);
  return parseTokenPayload(await response.json());
}

async function refreshSoopToken(refreshToken: string) {
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: requiredEnv('SOOP_DONATION_CLIENT_ID'),
    client_secret: requiredEnv('SOOP_DONATION_CLIENT_SECRET'),
    refresh_token: refreshToken,
  });
  const response = await fetch(TOKEN_URL, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body,
  });
  if (!response.ok) throw new Error(`TOKEN_REFRESH_FAILED:${response.status}`);
  return parseTokenPayload(await response.json(), refreshToken);
}

async function stationId(accessToken: string) {
  const response = await fetch(STATION_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ access_token: accessToken }),
  });
  if (!response.ok) throw new Error(`STATION_LOOKUP_FAILED:${response.status}`);
  const payload = await response.json();
  if (payload?.result !== 1) throw new Error('STATION_LOOKUP_INVALID');
  const id = extractSoopLoginId(payload?.data?.profile_image);
  if (!id) throw new Error('STATION_ID_MISSING');
  return id;
}

async function encryptionKey() {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(requiredEnv('SOOP_BRIDGE_ENCRYPTION_KEY')));
  return crypto.subtle.importKey('raw', digest, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

async function encryptToken(value: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await encryptionKey(), encoder.encode(value));
  return { ciphertext: base64Url(new Uint8Array(encrypted)), iv: base64Url(iv) };
}

async function decryptToken(ciphertext: string, iv: string) {
  const decrypted = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: fromBase64Url(iv) }, await encryptionKey(), fromBase64Url(ciphertext),
  );
  return decoder.decode(decrypted);
}

function bridgePageRedirect(code: string, value = '') {
  const page = new URL(requiredEnv('SOOP_BRIDGE_PAGE_URL'));
  page.hash = `${code}=${encodeURIComponent(value)}`;
  return new Response(null, {
    status: 302,
    headers: { Location: page.toString(), 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' },
  });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin');
  if (origin && !allowedOrigins().has(origin)) return json(req, { ok: false, error: '허용되지 않은 출처입니다.' }, 403);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(req) });

  const url = new URL(req.url);
  if (req.method === 'GET' && url.searchParams.get('action') === 'callback') {
    try {
      const state = await verifyToken(url.searchParams.get('state') ?? '', 'soop-oauth');
      const code = safeText(url.searchParams.get('code'), 512);
      if (!state?.userId || !state?.soopId || !code) return bridgePageRedirect('error', 'auth');
      const tokens = await exchangeSoopToken(code);
      const connectedSoopId = await stationId(tokens.accessToken);
      if (connectedSoopId !== state.soopId) return bridgePageRedirect('error', 'mismatch');
      const exchange = randomToken();
      const encrypted = await encryptToken(tokens.accessToken);
      const supabase = adminClient();
      const { error } = await supabase.from('gacha_s2_soop_oauth_exchanges').insert({
        exchange_hash: await sha256Hex(exchange),
        bridge_user_id: state.userId,
        soop_id: state.soopId,
        access_token_ciphertext: encrypted.ciphertext,
        access_token_iv: encrypted.iv,
        expires_at: new Date(Date.now() + 2 * 60 * 1000).toISOString(),
      });
      if (error) throw new Error(`EXCHANGE_STORE_FAILED:${error.code ?? 'unknown'}`);
      // Persist the refresh_token so the bridge can silently mint new access tokens later
      // instead of forcing the streamer to click through SOOP OAuth again every session.
      if (tokens.refreshToken) {
        const encryptedRefresh = await encryptToken(tokens.refreshToken);
        await supabase.from('gacha_s2_streamer_bridges').update({
          soop_refresh_token_ciphertext: encryptedRefresh.ciphertext,
          soop_refresh_token_iv: encryptedRefresh.iv,
          soop_refresh_updated_at: new Date().toISOString(),
        }).eq('user_id', state.userId);
      }
      return bridgePageRedirect('exchange', exchange);
    } catch (error) {
      console.error('SOOP_CALLBACK_FAILED', error instanceof Error ? error.message : String(error));
      return bridgePageRedirect('error', 'soop');
    }
  }

  if (req.method !== 'POST') return json(req, { ok: false, error: 'POST 요청만 허용합니다.' }, 405);
  let body: Record<string, unknown>;
  try {
    body = await readBody(req);
  } catch {
    return json(req, { ok: false, error: '요청 형식이 올바르지 않습니다.' }, 400);
  }
  const action = safeText(body.action, 40);
  const supabase = adminClient();

  if (action === 'authenticate') {
    const key = safeText(body.key, 256);
    if (!key) return json(req, { ok: false, error: '브리지 KEY가 필요합니다.' }, 400);
    const { data, error } = await supabase.rpc('gacha_s2_authenticate_streamer_bridge', {
      p_key_hash: await sha256Hex(key), p_rate_key: await rateKey(req),
    });
    if (error) return json(req, { ok: false, error: '브리지 인증 처리 실패' }, 500);
    if (!data?.ok) return json(req, { ok: false, code: data?.code, retryAfterSeconds: data?.retryAfterSeconds, error: data?.code === 'RATE_LIMITED' ? '잠시 후 다시 시도하세요.' : '유효하지 않은 브리지 KEY입니다.' }, data?.code === 'RATE_LIMITED' ? 429 : 401);
    const session = await signedToken({
      type: 'bridge', userId: data.userId, soopId: data.soopId,
      nonce: randomToken(16), exp: Date.now() + 4 * 60 * 60 * 1000,
    });
    return json(req, { ok: true, session, soopId: data.soopId });
  }

  const session = await verifyToken(bridgeToken(req), 'bridge');
  if (!session?.userId || !session?.soopId) return json(req, { ok: false, error: '브리지 인증이 만료되었습니다.' }, 401);

  if (action === 'soopStart') {
    const state = await signedToken({
      type: 'soop-oauth', userId: session.userId, soopId: session.soopId,
      nonce: randomToken(16), exp: Date.now() + 10 * 60 * 1000,
    });
    const params = new URLSearchParams({
      client_id: requiredEnv('SOOP_DONATION_CLIENT_ID'),
      redirect_uri: requiredEnv('SOOP_DONATION_REDIRECT_URI'),
      response_type: 'code', state,
    });
    return json(req, { ok: true, authorizeUrl: `${AUTH_URL}?${params}` });
  }

  if (action === 'exchange') {
    const exchange = safeText(body.exchange, 256);
    const { data, error } = await supabase.rpc('gacha_s2_consume_soop_exchange', {
      p_bridge_user_id: session.userId, p_exchange_hash: await sha256Hex(exchange),
    });
    if (error || !data || data.soopId !== session.soopId) return json(req, { ok: false, error: 'SOOP 연결 교환코드가 만료되었습니다.' }, 401);
    return json(req, {
      ok: true,
      credentials: {
        clientId: requiredEnv('SOOP_DONATION_CLIENT_ID'),
        accessToken: await decryptToken(data.ciphertext, data.iv),
        soopId: data.soopId,
      },
    });
  }

  if (action === 'refreshToken') {
    const { data: bridgeRow, error: bridgeError } = await supabase
      .from('gacha_s2_streamer_bridges')
      .select('soop_refresh_token_ciphertext, soop_refresh_token_iv')
      .eq('user_id', session.userId)
      .maybeSingle();
    if (bridgeError || !bridgeRow?.soop_refresh_token_ciphertext || !bridgeRow?.soop_refresh_token_iv) {
      return json(req, { ok: false, code: 'REFRESH_UNAVAILABLE', error: 'SOOP 재연동이 필요합니다.' }, 401);
    }
    try {
      const storedRefreshToken = await decryptToken(bridgeRow.soop_refresh_token_ciphertext, bridgeRow.soop_refresh_token_iv);
      const tokens = await refreshSoopToken(storedRefreshToken);
      const encryptedRefresh = await encryptToken(tokens.refreshToken);
      await supabase.from('gacha_s2_streamer_bridges').update({
        soop_refresh_token_ciphertext: encryptedRefresh.ciphertext,
        soop_refresh_token_iv: encryptedRefresh.iv,
        soop_refresh_updated_at: new Date().toISOString(),
      }).eq('user_id', session.userId);
      return json(req, {
        ok: true,
        credentials: {
          clientId: requiredEnv('SOOP_DONATION_CLIENT_ID'),
          accessToken: tokens.accessToken,
          soopId: session.soopId,
        },
      });
    } catch (error) {
      console.error('SOOP_TOKEN_REFRESH_FAILED', error instanceof Error ? error.message : String(error));
      return json(req, { ok: false, code: 'REFRESH_FAILED', error: 'SOOP 재연동이 필요합니다.' }, 401);
    }
  }

  if (action === 'donation') {
    const eventId = safeText(body.eventId, 255);
    const eventAction = safeText(body.eventAction, 40);
    const senderSoopId = safeText(body.senderSoopId, 100);
    const recipientSoopId = safeText(body.recipientSoopId, 100);
    const amount = Number(body.amount);
    if (!eventId || !['BALLOON_GIFTED', 'BATTLE_MISSION_GIFTED'].includes(eventAction)
      || !senderSoopId || recipientSoopId !== session.soopId || !Number.isSafeInteger(amount) || amount < 1 || amount > 100000) {
      return json(req, { ok: false, error: '유효하지 않은 후원 이벤트입니다.' }, 400);
    }
    const minuteAgo = new Date(Date.now() - 60_000).toISOString();
    const { count } = await supabase.from('gacha_s2_soop_donation_events')
      .select('event_id', { count: 'exact', head: true })
      .eq('bridge_user_id', session.userId).gte('created_at', minuteAgo);
    if ((count ?? 0) >= 120) return json(req, { ok: false, error: '후원 이벤트 처리 한도를 초과했습니다.' }, 429);
    const { data, error } = await supabase.rpc('gacha_s2_apply_soop_donation', {
      p_bridge_user_id: session.userId,
      p_event_id: eventId,
      p_action: eventAction,
      p_sender_soop_id: senderSoopId,
      p_recipient_soop_id: recipientSoopId,
      p_amount: amount,
    });
    if (error) return json(req, { ok: false, error: '후원 포인트 처리 실패' }, 500);
    return json(req, { ok: true, ...data });
  }

  return json(req, { ok: false, error: '지원하지 않는 요청입니다.' }, 400);
});
