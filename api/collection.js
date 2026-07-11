// POST /api/collection {key}
const { sendJson, readBody } = require('../lib/http');
const { getUserByKey, getCollection, getMemberRewards } = require('../lib/supabase');
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

    const cards = {};
    const first = {};
    for (const row of await getCollection(user.id)) {
      cards[row.card_id] = row.count;
      if (row.first_at) first[row.card_id] = row.first_at;
    }
    let claimed = [];
    try {
      claimed = (await getMemberRewards(user.id)).map((row) => row.member);
    } catch (rewardError) {
      console.error('collection rewards read failed', rewardError?.message || rewardError);
    }
    return sendJson(res, 200, { cards, first, claimed });
  } catch (e) {
    return serverError(res, 'collection', e, '도감 조회에 실패했습니다');
  }
};
