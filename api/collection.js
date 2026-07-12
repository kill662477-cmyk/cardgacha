// POST /api/collection {key}
const { sendJson, readBody } = require('../lib/http');
const { getUserByKey, getCollection, getMemberRewards, getUserSerials, getCardCounters } = require('../lib/supabase');
const { enforceRateLimit, serverError } = require('../lib/security');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    if (!await enforceRateLimit(req, res, 'collection-ip', 90, 60)) return;
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key가 필요합니다' });
    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });
    if (!await enforceRateLimit(req, res, 'collection-user', 60, 60, user.id)) return;

    const includeDetails = body.includeDetails !== false;
    const [collectionRows, rewardRows, serialRows] = await Promise.all([
      getCollection(user.id),
      includeDetails ? getMemberRewards(user.id).catch((error) => {
        console.error('collection rewards read failed', error?.message || error);
        return [];
      }) : Promise.resolve([]),
      includeDetails ? getUserSerials(user.id).catch((error) => {
        console.error('collection serials read failed', error?.message || error);
        return [];
      }) : Promise.resolve([]),
    ]);

    const cards = {};
    const first = {};
    for (const row of collectionRows) {
      cards[row.card_id] = row.count;
      if (row.first_at) first[row.card_id] = row.first_at;
    }
    const claimed = rewardRows.map((row) => row.member);

    // 카드 시리얼(넘버링): 보유 각 장의 시리얼 + 카드별 총 발행 수. migration8 전이면 graceful 생략.
    const serials = {};
    const issued = {};
    if (includeDetails) {
      for (const row of serialRows) (serials[row.card_id] = serials[row.card_id] || []).push(row.serial);
      const ownedIds = Object.keys(cards);
      try {
        if (ownedIds.length) {
          for (const row of await getCardCounters(ownedIds)) issued[row.card_id] = row.issued;
        }
      } catch (serialError) {
        console.error('collection counters read failed', serialError?.message || serialError);
      }
    }
    return sendJson(res, 200, { cards, first, claimed, serials, issued });
  } catch (e) {
    return serverError(res, 'collection', e, '도감 조회에 실패했습니다');
  }
};
