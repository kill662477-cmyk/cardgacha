// The one-time prediction event has ended. Keep the route so stale clients
// receive a terminal response without making any Supabase requests.
const { sendJson } = require('../lib/http');

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'public, max-age=300, s-maxage=3600');
  return sendJson(res, 410, { error: '종료된 이벤트입니다' });
};
