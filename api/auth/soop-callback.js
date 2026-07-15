// GET /api/auth/soop-callback?code=xxx
//  1. code -> access_token 교환 (auth/token)
//  2. access_token -> 유저 정보 (user/stationinfo)
//  3. profile_image URL 에서 파싱한 로그인ID(=soop_id)로 gacha_users 조회:
//       없으면 신규 생성(닉네임=user_nick, points=5000, 새 login_key 발급)
//       있으면 닉네임 갱신 + login_key 회전(새 key 발급)
//     로그인ID 추출 실패 시 계정을 만들거나 조회하지 않고 sooperr 로 리다이렉트한다
//     (station_name 폴백 금지 → 중복계정 재발 방지).
//  4. 성공 -> 302 `/#soop={login_key}` (신규는 &new=1),  실패 -> 302 `/#sooperr=1`
//
// login_key 를 URL fragment 로 전달하는 이유: fragment 는 서버로 전송되지 않고
// (Referrer-Policy:no-referrer 와 함께) 서버 로그/리퍼러에 key 가 남지 않는다.
const { loadEnv } = require('../../lib/env');
const { getQuery, sendJson } = require('../../lib/http');
const { rejectDuringMaintenance } = require('../../lib/maintenance');
const { newKey } = require('../../lib/gacha');
const {
  getUserBySoopId,
  insertSoopUser,
  rotateSoopUserKey,
} = require('../../lib/supabase');
const { enforceRateLimit } = require('../../lib/security');
const { extractSoopLoginId } = require('../../lib/soop');

loadEnv();

const TOKEN_URL = 'https://openapi.sooplive.com/auth/token';
const STATION_URL = 'https://openapi.sooplive.com/user/stationinfo';

function redirect(res, hash) {
  res.statusCode = 302;
  res.setHeader('Location', `/${hash}`);
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Cache-Control', 'no-store');
  res.end();
}

async function exchangeToken({ clientId, clientSecret, redirectUri, code }) {
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: clientId,
    client_secret: clientSecret,
    redirect_uri: redirectUri,
    code,
  });
  const r = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!r.ok) throw new Error(`token exchange failed: ${r.status}`);
  const j = await r.json();
  if (!j || !j.access_token) throw new Error('token exchange: no access_token');
  return j.access_token;
}

async function fetchStationInfo(accessToken) {
  const body = new URLSearchParams({ access_token: accessToken });
  const r = await fetch(STATION_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!r.ok) throw new Error(`stationinfo failed: ${r.status}`);
  const j = await r.json();
  if (!j || j.result !== 1 || !j.data) throw new Error('stationinfo: bad result');
  const data = j.data;
  // 계정 식별은 로그인ID 기준. profile_image URL 에서 파싱하며, 실패 시 폴백 없이 중단.
  const soopId = extractSoopLoginId(data.profile_image);
  if (!soopId) {
    console.error('soop-callback: profile_image 에서 로그인ID 추출 실패', data.profile_image);
    throw new Error('stationinfo: no login id');
  }
  const nick = (data.user_nick || '').toString().trim() || soopId;
  return { soopId, nick };
}

module.exports = async function handler(req, res) {
  if (rejectDuringMaintenance(res, sendJson)) return;
  if (req.method !== 'GET') {
    res.statusCode = 405;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(JSON.stringify({ error: 'method not allowed' }));
    return;
  }

  const clientId = process.env.SOOP_CLIENT_ID;
  const clientSecret = process.env.SOOP_CLIENT_SECRET;
  const redirectUri = process.env.SOOP_REDIRECT_URI;
  if (!clientId || !clientSecret || !redirectUri) {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(JSON.stringify({ error: '숲 로그인이 아직 설정되지 않았습니다.' }));
    return;
  }

  try {
    // token 교환은 외부 API 호출을 유발하므로 IP 기준 rate limit 적용.
    if (!await enforceRateLimit(req, res, 'soop-callback', 20, 60)) return;

    const code = (getQuery(req).code || '').toString().trim();
    if (!code) return redirect(res, '#sooperr=1');

    const accessToken = await exchangeToken({ clientId, clientSecret, redirectUri, code });
    const { soopId, nick } = await fetchStationInfo(accessToken);

    const ip = req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '';
    const key = newKey();

    const existing = await getUserBySoopId(soopId);
    if (existing) {
      await rotateSoopUserKey(existing.id, nick, key, ip);
      return redirect(res, `#soop=${encodeURIComponent(key)}`);
    }

    await insertSoopUser(soopId, nick, key, ip);
    return redirect(res, `#soop=${encodeURIComponent(key)}&new=1`);
  } catch (e) {
    console.error('soop-callback error', e?.message || e);
    return redirect(res, '#sooperr=1');
  }
};
