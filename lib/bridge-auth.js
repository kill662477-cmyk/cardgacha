const crypto = require('crypto');
const { loadEnv } = require('./env');

loadEnv();

const SESSION_COOKIE = 'gacha_soop_bridge';
const TOKEN_COOKIE = 'gacha_soop_bridge_token';
const SESSION_TTL = 12 * 60 * 60;
const TOKEN_TTL = 2 * 60 * 60;

function secret() {
  return process.env.SOOP_DONATION_BRIDGE_SECRET || '';
}

function encode(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function sign(value) {
  return crypto.createHmac('sha256', secret()).update(value).digest('base64url');
}

function issue(payload, ttl) {
  if (!secret()) return '';
  const encoded = encode({ ...payload, exp: Math.floor(Date.now() / 1000) + ttl });
  return `${encoded}.${sign(encoded)}`;
}

function verify(token) {
  if (!secret() || !token) return null;
  const [encoded, signature] = String(token).split('.');
  if (!encoded || !signature) return null;
  const expected = sign(encoded);
  const left = Buffer.from(signature);
  const right = Buffer.from(expected);
  if (left.length !== right.length || !crypto.timingSafeEqual(left, right)) return null;
  try {
    const value = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
    if (!value || !Number.isInteger(value.exp) || value.exp <= Math.floor(Date.now() / 1000)) return null;
    return value;
  } catch (e) {
    return null;
  }
}

function cookies(req) {
  const raw = req.headers.cookie || '';
  const values = {};
  for (const part of raw.split(';')) {
    const index = part.indexOf('=');
    if (index < 1) continue;
    values[part.slice(0, index).trim()] = decodeURIComponent(part.slice(index + 1).trim());
  }
  return values;
}

function sessionFrom(req) {
  return verify(cookies(req)[SESSION_COOKIE]);
}

function tokenFrom(req) {
  return verify(cookies(req)[TOKEN_COOKIE]);
}

function appendCookie(res, value) {
  const existing = res.getHeader('Set-Cookie');
  const values = Array.isArray(existing) ? existing : existing ? [existing] : [];
  values.push(value);
  res.setHeader('Set-Cookie', values);
}

function cookie(name, value, maxAge, sameSite = 'Strict') {
  const secure = process.env.VERCEL || process.env.NODE_ENV === 'production' ? '; Secure' : '';
  return `${name}=${encodeURIComponent(value)}; Path=/api/bridge; Max-Age=${maxAge}; HttpOnly; SameSite=${sameSite}${secure}`;
}

function setSession(res, soopId) {
  const nonce = crypto.randomBytes(12).toString('base64url');
  // OAuth 제공자에서 돌아오는 최상위 GET 요청에도 브릿지 세션이 필요하다.
  appendCookie(res, cookie(SESSION_COOKIE, issue({ type: 'bridge', nonce, soopId }, SESSION_TTL), SESSION_TTL, 'Lax'));
  return nonce;
}

function setSoopToken(res, accessToken, soopId) {
  appendCookie(res, cookie(TOKEN_COOKIE, issue({ type: 'soop', accessToken, soopId }, TOKEN_TTL), TOKEN_TTL));
}

function clearBridgeCookies(res) {
  appendCookie(res, cookie(SESSION_COOKIE, '', 0));
  appendCookie(res, cookie(TOKEN_COOKIE, '', 0));
}

module.exports = {
  SESSION_TTL,
  clearBridgeCookies,
  secret,
  sessionFrom,
  setSession,
  setSoopToken,
  tokenFrom,
};
