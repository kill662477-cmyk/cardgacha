const crypto = require('crypto');
const { sendJson } = require('./http');
const { rpc } = require('./supabase');

function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  const value = Array.isArray(forwarded) ? forwarded[0] : forwarded;
  return String(value || req.socket?.remoteAddress || 'unknown').split(',')[0].trim();
}

function bucketPart(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex').slice(0, 24);
}

async function enforceRateLimit(req, res, action, limit, seconds, subject) {
  const identity = subject || getClientIp(req);
  const rows = await rpc('gacha_take_rate_limit', {
    p_bucket: `${action}:${bucketPart(identity)}`,
    p_limit: limit,
    p_window_seconds: seconds,
  });
  if (rows?.[0]?.allowed) return true;
  sendJson(res, 429, { error: '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.' });
  return false;
}

function serverError(res, area, error, message) {
  console.error(`${area} error`, error?.message || error);
  return sendJson(res, 500, { error: message });
}

module.exports = { enforceRateLimit, serverError };
