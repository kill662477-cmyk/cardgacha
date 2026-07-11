// GET /api/announcements -> {items:[{nickname,member,rarity,card_id,created_at}]}
// 최근 24시간 내 UR 이상 레어 드랍 최신 20건.
const { sendJson } = require('../lib/http');
const { getRecentAnnouncements } = require('../lib/supabase');

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const rows = await getRecentAnnouncements(20);
    res.setHeader('Cache-Control', 'no-store');
    return sendJson(res, 200, { items: rows || [] });
  } catch (e) {
    console.error('announcements error', e);
    // 티커는 필수 아니므로 빈 목록으로 폴백
    return sendJson(res, 200, { items: [] });
  }
};
