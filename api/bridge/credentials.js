const { sendJson } = require('../../lib/http');
const { sessionFrom, tokenFrom } = require('../../lib/bridge-auth');

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method not allowed' });
  const session = sessionFrom(req);
  if (!session?.soopId) return sendJson(res, 401, { error: '방송인 브리지 키 인증이 필요합니다' });
  const token = tokenFrom(req);
  if (!token?.accessToken) return sendJson(res, 404, { error: 'SOOP 연결이 필요합니다' });
  if (token.soopId !== session.soopId) return sendJson(res, 403, { error: '브리지 키와 SOOP 계정이 일치하지 않습니다' });
  const clientId = process.env.SOOP_CLIENT_ID || '';
  if (!clientId) return sendJson(res, 503, { error: 'SOOP_CLIENT_ID가 설정되지 않았습니다' });
  return sendJson(res, 200, { clientId, accessToken: token.accessToken, soopId: token.soopId });
};
