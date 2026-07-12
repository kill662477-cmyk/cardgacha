const { sendJson } = require('../../lib/http');
const { sessionFrom } = require('../../lib/bridge-auth');

const AUTH_URL = 'https://openapi.sooplive.com/auth/code';

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method not allowed' });
  if (!sessionFrom(req)?.soopId) return sendJson(res, 401, { error: '방송인 브리지 키 인증이 필요합니다' });

  const clientId = process.env.SOOP_CLIENT_ID;
  const clientSecret = process.env.SOOP_CLIENT_SECRET;
  const redirectUri = process.env.SOOP_DONATION_REDIRECT_URI;
  if (!clientId || !clientSecret || !redirectUri) {
    return sendJson(res, 503, { error: '후원용 SOOP 환경변수가 설정되지 않았습니다' });
  }

  const params = new URLSearchParams({ client_id: clientId, redirect_uri: redirectUri, response_type: 'code' });
  res.statusCode = 302;
  res.setHeader('Location', `${AUTH_URL}?${params}`);
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Cache-Control', 'no-store');
  res.end();
};
