// GET /api/collection?key= -> {cards:{cardId:count}, first:{cardId:iso}, claimed:[member]}
const { sendJson, getQuery } = require('../lib/http');
const { getUserByKey, getCollection, getMemberRewards } = require('../lib/supabase');

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const q = getQuery(req);
    const key = (q.key || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key가 필요합니다' });

    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });

    const rows = await getCollection(user.id);
    const cards = {};
    const first = {};
    for (const r of rows) {
      cards[r.card_id] = r.count;
      if (r.first_at) first[r.card_id] = r.first_at;
    }

    // 수령한 도감 완성 보상 멤버 (migration2 미실행 시 빈 배열로 graceful)
    let claimed = [];
    try {
      const rewards = await getMemberRewards(user.id);
      claimed = rewards.map((r) => r.member);
    } catch (e) { /* 테이블 없음: 기능 비활성 */ }

    return sendJson(res, 200, { cards, first, claimed });
  } catch (e) {
    console.error('collection error', e);
    return sendJson(res, 500, { error: '도감 조회 실패', detail: String(e.message || e) });
  }
};
