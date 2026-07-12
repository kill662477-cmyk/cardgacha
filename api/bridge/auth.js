const crypto = require('crypto');
const { readBody, sendJson } = require('../../lib/http');
const { enforceRateLimit } = require('../../lib/security');
const { getBridgeKeyByHash } = require('../../lib/supabase');
const { secret, setSession } = require('../../lib/bridge-auth');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  if (!await enforceRateLimit(req, res, 'soop-bridge-auth', 8, 300)) return;
  if (!secret()) return sendJson(res, 503, { error: '후원 브리지 서명 키가 설정되지 않았습니다' });
  const body = await readBody(req);
  const bridgeKey = String(body.bridgeKey || '').trim();
  if (!bridgeKey) return sendJson(res, 400, { error: '브리지 키를 입력하세요' });
  const keyHash = crypto.createHash('sha256').update(bridgeKey).digest('hex');
  const record = await getBridgeKeyByHash(keyHash);
  if (!record?.active || !record.soop_id) return sendJson(res, 401, { error: '유효하지 않거나 폐기된 브리지 키입니다' });
  setSession(res, record.soop_id);
  return sendJson(res, 200, { ok: true, soopId: record.soop_id });
};
