// GET /api/public-config -> {url, anonKey}
// 티커 실시간(Supabase Realtime) 구독용 공개 설정. anon 키는 공개 정보이며 RLS 로 보호됨.
const { sendJson } = require('../lib/http');
const { loadEnv } = require('../lib/env');
const { MAINTENANCE_AT, isMaintenance } = require('../lib/maintenance');
loadEnv();

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method not allowed' });
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
  const anonKey =
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
    '';
  res.setHeader('Cache-Control', 'no-store');
  return sendJson(res, 200, {
    url,
    anonKey,
    serverNow: new Date().toISOString(),
    maintenanceAt: MAINTENANCE_AT,
    maintenance: isMaintenance(),
  });
};
