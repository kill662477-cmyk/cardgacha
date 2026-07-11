// POST /api/dismantle {key, cardId, count}         단건 분해
// POST /api/dismantle {key, mode:"all"}             전체 초과분 일괄 분해
// -> {points, refund, dismantled:[{cardId,count,refund}], collection:{id:count}}
// 각 카드 최소 1장 보존. 환급액/수량 검증은 전부 서버에서 계산한다.
const { sendJson, readBody } = require('../lib/http');
const { DISMANTLE_REFUND, cardById } = require('../lib/gacha');
const { getUserByKey, updateUser, getCollection, setCollectionCounts } = require('../lib/supabase');

function refundOf(cardId) {
  const card = cardById(cardId);
  if (!card) return null;
  return DISMANTLE_REFUND[card.rarity] || 0;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });

    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });

    const rows = await getCollection(user.id);
    const owned = {}; // card_id -> count
    for (const r of rows) owned[r.card_id] = r.count;

    const mode = (body.mode || '').toString();
    let updates = []; // {user_id, card_id, count}
    let dismantled = [];
    let totalRefund = 0;

    if (mode === 'all') {
      for (const [cardId, count] of Object.entries(owned)) {
        const excess = count - 1;
        if (excess <= 0) continue;
        const per = refundOf(cardId);
        if (per == null) continue; // cards.json 에 없는 카드는 건너뜀
        const gain = per * excess;
        totalRefund += gain;
        updates.push({ user_id: user.id, card_id: cardId, count: 1 });
        dismantled.push({ cardId, count: excess, refund: gain });
      }
      if (!updates.length) return sendJson(res, 400, { error: '분해할 중복 카드가 없습니다' });
    } else {
      const cardId = (body.cardId || '').toString().trim();
      const reqCount = Math.floor(Number(body.count));
      if (!cardId) return sendJson(res, 400, { error: 'cardId가 필요합니다' });
      if (!Number.isFinite(reqCount) || reqCount < 1) {
        return sendJson(res, 400, { error: '분해 수량이 올바르지 않습니다' });
      }
      const have = owned[cardId] || 0;
      const maxDismantle = have - 1; // 최소 1장 보존
      if (maxDismantle < 1) return sendJson(res, 400, { error: '분해할 수 있는 중복분이 없습니다' });
      if (reqCount > maxDismantle) {
        return sendJson(res, 400, { error: `최대 ${maxDismantle}장까지 분해할 수 있습니다` });
      }
      const per = refundOf(cardId);
      if (per == null) return sendJson(res, 400, { error: '알 수 없는 카드입니다' });
      const gain = per * reqCount;
      totalRefund += gain;
      updates.push({ user_id: user.id, card_id: cardId, count: have - reqCount });
      dismantled.push({ cardId, count: reqCount, refund: gain });
    }

    // 컬렉션 수량 갱신 + 포인트 지급
    await setCollectionCounts(updates);
    const updated = await updateUser(user.id, { points: user.points + totalRefund });

    // 갱신된 최종 수량 맵 반환 (프론트 로컬 동기화)
    const collection = {};
    for (const [cardId, count] of Object.entries(owned)) collection[cardId] = count;
    for (const u of updates) collection[u.card_id] = u.count;

    return sendJson(res, 200, { points: updated.points, refund: totalRefund, dismantled, collection });
  } catch (e) {
    console.error('dismantle error', e);
    return sendJson(res, 500, { error: '분해 실패', detail: String(e.message || e) });
  }
};
