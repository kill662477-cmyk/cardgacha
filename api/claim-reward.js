// POST /api/claim-reward {key, member}
const { sendJson, readBody } = require('../lib/http');
const { getCards, MEMBER_REWARDS } = require('../lib/gacha');
const { getUserByKey, getCollection, rpc } = require('../lib/supabase');
const { enforceRateLimit, serverError } = require('../lib/security');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    const member = (body.member || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });
    if (!member) return sendJson(res, 400, { error: 'member가 필요합니다' });
    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });
    if (!await enforceRateLimit(req, res, 'reward-user', 6, 60, user.id)) return;

    const cards = getCards();
    const targetCards = cards.filter((card) => card.member === member);
    if (!targetCards.length) return sendJson(res, 400, { error: '알 수 없는 멤버입니다' });
    const reward = MEMBER_REWARDS[member] || 0;
    const owned = new Set((await getCollection(user.id)).filter((row) => row.count > 0).map((row) => row.card_id));
    if (!targetCards.every((card) => owned.has(card.id))) {
      return sendJson(res, 400, { error: '아직 도감을 완성하지 않았습니다', ok: false });
    }

    const rows = await rpc('gacha_claim_reward', {
      p_user_id: user.id,
      p_member: member,
      p_reward: reward,
      p_ranking_bonus: 1000,
    });
    const result = rows?.[0];
    if (!result) throw new Error('reward commit failed');
    if (!result.claimed) return sendJson(res, 200, { ok: false, reason: 'claimed', message: '이미 수령한 보상입니다' });
    return sendJson(res, 200, { ok: true, points: result.points, reward, member });
  } catch (e) {
    return serverError(res, 'claim-reward', e, '보상 수령에 실패했습니다');
  }
};
