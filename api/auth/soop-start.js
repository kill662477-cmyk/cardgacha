// GET /api/auth/soop-start -> 302 SOOP 인증 페이지로 리다이렉트
// SOOP 로그인 후 포털에 사전등록된 redirect_uri(SOOP_REDIRECT_URI)로 ?code= 가 전달된다.
// (SOOP OpenAPI 는 state 파라미터를 지원하지 않는다.)
const { loadEnv } = require('../../lib/env');
const { sendJson } = require('../../lib/http');
const { rejectDuringMaintenance } = require('../../lib/maintenance');

loadEnv();

const AUTH_URL = 'https://openapi.sooplive.com/auth/code';

module.exports = async function handler(req, res) {
  if (rejectDuringMaintenance(res, sendJson)) return;
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method not allowed' });

  const clientId = process.env.SOOP_CLIENT_ID;
  if (!clientId || !process.env.SOOP_CLIENT_SECRET || !process.env.SOOP_REDIRECT_URI) {
    return sendJson(res, 503, { error: '숲 로그인이 아직 설정되지 않았습니다.' });
  }

  const location = `${AUTH_URL}?client_id=${encodeURIComponent(clientId)}`;
  res.statusCode = 302;
  res.setHeader('Location', location);
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Cache-Control', 'no-store');
  res.end();
};
