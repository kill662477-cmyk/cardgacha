// POST /api/dismantle {key, cardId, count} or {key, mode:"all"}
const { sendJson, readBody } = require('../lib/http');
const { DISMANTLE_REFUND, cardById } = require('../lib/gacha');
const { getUserByKey, getCollection, rpc } = require('../lib/supabase');
const { enforceRateLimit, serverError } = require('../lib/security');

function refundOf(cardId) {
  const card = cardById(cardId);
  return card ? DISMANTLE_REFUND[card.rarity] || 0 : null;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });
    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });
    if (!await enforceRateLimit(req, res, 'dismantle-user', 10, 60, user.id)) return;

    const owned = {};
    for (const row of await getCollection(user.id)) owned[row.card_id] = row.count;
    const mode = (body.mode || '').toString();
    const changes = [];
    const dismantled = [];
    let refund = 0;

    const addChange = (cardId, count) => {
      const have = owned[cardId] || 0;
      const per = refundOf(cardId);
      if (per == null) return false;
      const gain = per * count;
      changes.push({ card_id: cardId, expected_count: have, new_count: have - count, refund: gain });
      dismantled.push({ cardId, count, refund: gain });
      refund += gain;
      return true;
    };

    if (mode === 'all') {
      for (const [cardId, count] of Object.entries(owned)) {
        const excess = count - 1;
        if (excess > 0) addChange(cardId, excess);
      }
      if (!changes.length) return sendJson(res, 400, { error: '분해할 중복 카드가 없습니다' });
    } else {
      const cardId = (body.cardId || '').toString().trim();
      const count = Math.floor(Number(body.count));
      if (!cardId) return sendJson(res, 400, { error: 'cardId가 필요합니다' });
      if (!Number.isFinite(count) || count < 1) return sendJson(res, 400, { error: '분해 수량이 올바르지 않습니다' });
      const max = (owned[cardId] || 0) - 1;
      if (max < 1) return sendJson(res, 400, { error: '분해할 수 있는 중복분이 없습니다' });
      if (count > max) return sendJson(res, 400, { error: `최대 ${max}장까지 분해할 수 있습니다` });
      if (!addChange(cardId, count)) return sendJson(res, 400, { error: '알 수 없는 카드입니다' });
    }

    const rows = await rpc('gacha_dismantle', { p_user_id: user.id, p_updates: changes });
    const updated = rows?.[0];
    if (!updated) throw new Error('dismantle commit failed');
    const collection = { ...owned };
    for (const change of changes) collection[change.card_id] = change.new_count;
    return sendJson(res, 200, { points: updated.points, refund, dismantled, collection });
  } catch (e) {
    if (e?.code === 'P0001') return sendJson(res, 409, { error: '카드 상태가 변경되었습니다. 다시 시도해주세요.' });
    return serverError(res, 'dismantle', e, '분해에 실패했습니다');
  }
};
