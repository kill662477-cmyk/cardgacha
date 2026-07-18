// Season 2 일반 유저 SOOP 숲 로그인 (스트리머 후원 브릿지 soop-bridge 와는 별개).
//
// 플로우 (시즌1의 OAuth 동작을 시즌2 인프라에 맞춰 재구성):
//   GET ?action=start    -> 302 SOOP 인증 페이지 (state 없음, 시즌1 방식).
//   GET ?action=callback -> code 교환 -> stationinfo soop_id 추출 ->
//     access_token AES-GCM 암호화 후 gacha_s2_soop_auth_exchanges에 2분 TTL 저장 ->
//     일회성 exchange 코드를 #soopauth={code} fragment로 클라이언트 리다이렉트.
//   실패 -> #soopautherr=1
//
// 클라이언트는 fragment의 exchange 코드로 session-exchange(soop 분기) -> gacha_s2_bind_soop_session RPC 호출.
// CSRF 방어: state 없는 대신 rate limit(IP) + 매 로그인 exchange 코드 회전 + Referrer-Policy:no-referrer.

import { createClient } from '@supabase/supabase-js';

const AUTH_URL = 'https://openapi.sooplive.com/auth/code';
const TOKEN_URL = 'https://openapi.sooplive.com/auth/token';
const STATION_URL = 'https://openapi.sooplive.com/user/stationinfo';
const EXCHANGE_TTL_MS = 2 * 60 * 1000;
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
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
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

async function hmacHex(value: string, secretName: string) {
  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(requiredEnv(secretName)), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(value)));
  return [...signature].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function sha256Hex(value: string) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value)));
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function randomToken(byteLength = 32) {
  return base64Url(crypto.getRandomValues(new Uint8Array(byteLength)));
}

function rateKey(req: Request) {
  const ip = (req.headers.get('cf-connecting-ip') ?? req.headers.get('x-forwarded-for')?.split(',')[0] ?? 'unknown').trim();
  return hmacHex(ip, 'AUTH_RATE_LIMIT_PEPPER');
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

async function exchangeSoopToken(code: string) {
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: requiredEnv('SOOP_CLIENT_ID'),
    client_secret: requiredEnv('SOOP_CLIENT_SECRET'),
    redirect_uri: requiredEnv('SOOP_REDIRECT_URI'),
    code,
  });
  const response = await fetch(TOKEN_URL, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body,
  });
  if (!response.ok) throw new Error(`TOKEN_EXCHANGE_FAILED:${response.status}`);
  const payload = await response.json();
  if (!payload?.access_token) throw new Error('TOKEN_EXCHANGE_EMPTY');
  return String(payload.access_token);
}

async function fetchStationInfo(accessToken: string) {
  const response = await fetch(STATION_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ access_token: accessToken }),
  });
  if (!response.ok) throw new Error(`STATION_LOOKUP_FAILED:${response.status}`);
  const payload = await response.json();
  if (payload?.result !== 1 || !payload?.data) throw new Error('STATION_LOOKUP_INVALID');
  const id = extractSoopLoginId(payload.data.profile_image);
  if (!id) throw new Error('STATION_ID_MISSING');
  const nick = safeText(payload.data.user_nick, 40) || id;
  return { soopId: id, nick };
}

async function encryptionKey() {
  // soop-bridge와 동일 키를 공유해 암호화 스택을 통일.
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(requiredEnv('SOOP_BRIDGE_ENCRYPTION_KEY')));
  return crypto.subtle.importKey('raw', digest, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

async function encryptToken(value: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await encryptionKey(), encoder.encode(value));
  return { ciphertext: base64Url(new Uint8Array(encrypted)), iv: base64Url(iv) };
}

function pageRedirect(hashKey: string, value = '') {
  const page = new URL(requiredEnv('SOOP_AUTH_PAGE_URL'));
  page.hash = `${hashKey}=${encodeURIComponent(value)}`;
  return new Response(null, {
    status: 302,
    headers: { Location: page.toString(), 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' },
  });
}

async function handleStart(): Promise<Response> {
  // SOOP OpenAPI는 state를 지원하지 않는다(시즌1 검증). client_id만 붙여 인증 페이지로 보낸다.
  const clientId = requiredEnv('SOOP_CLIENT_ID');
  const location = `${AUTH_URL}?client_id=${encodeURIComponent(clientId)}`;
  return new Response(null, {
    status: 302,
    headers: { Location: location, 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' },
  });
}

async function handleCallback(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const code = safeText(url.searchParams.get('code'), 512);
  if (!code) return pageRedirect('soopautherr', '1');

  // token 교환은 외부 API 호출이므로 IP 기준 rate limit (분당 20회).
  const supabase = adminClient();
  const rateKeyHash = await rateKey(req);
  const windowStart = new Date(Date.now() - 60 * 1000).toISOString();
  const { count: recentCount, error: countError } = await supabase
    .from('gacha_s2_soop_auth_rate_log')
    .select('id', { count: 'exact', head: true })
    .eq('rate_key', rateKeyHash)
    .gte('created_at', windowStart);
  if (countError) throw new Error(`RATE_LOOKUP_FAILED:${countError.code ?? 'unknown'}`);
  if ((recentCount ?? 0) >= 20) return pageRedirect('soopautherr', 'rate');

  const accessToken = await exchangeSoopToken(code);
  const { soopId, nick } = await fetchStationInfo(accessToken);

  const exchange = randomToken();
  const exchangeHash = await sha256Hex(exchange);
  const encrypted = await encryptToken(accessToken);

  const { error } = await supabase.from('gacha_s2_soop_auth_exchanges').insert({
    exchange_hash: exchangeHash,
    soop_id: soopId,
    nickname: nick,
    access_token_ciphertext: encrypted.ciphertext,
    access_token_iv: encrypted.iv,
    expires_at: new Date(Date.now() + EXCHANGE_TTL_MS).toISOString(),
  });
  if (error) throw new Error(`EXCHANGE_STORE_FAILED:${error.code ?? 'unknown'}`);

  // rate 로그는 best-effort. 실패해도 로그인 자체는 진행된다.
  await supabase.from('gacha_s2_soop_auth_rate_log').insert({ rate_key: rateKeyHash });

  return pageRedirect('soopauth', exchange);
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin');
  if (origin && !allowedOrigins().has(origin)) return json(req, { ok: false, error: '허용되지 않은 출처입니다.' }, 403);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== 'GET') return json(req, { ok: false, error: 'GET 요청만 허용합니다.' }, 405);

  const url = new URL(req.url);
  const action = url.searchParams.get('action');

  try {
    if (action === 'start') return await handleStart();
    if (action === 'callback') return await handleCallback(req);
    return json(req, { ok: false, error: '알 수 없는 요청입니다.' }, 400);
  } catch (error) {
    console.error('SOOP_AUTH_FAILED', error instanceof Error ? error.message : String(error));
    if (action === 'callback') return pageRedirect('soopautherr', '1');
    return json(req, { ok: false, error: 'SOOP 로그인 처리에 실패했습니다.' }, 500);
  }
});
