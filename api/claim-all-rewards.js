// POST /api/claim-all-rewards {key} -> claims every completed, unclaimed member reward.
const { sendJson, readBody } = require('../lib/http');
const { getCards, MEMBER_REWARDS } = require('../lib/gacha');
const { getUserByKey, getCollection, getMemberRewards, rpc } = require('../lib/supabase');
const { enforceRateLimit, serverError } = require('../lib/security');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    if (!await enforceRateLimit(req, res, 'reward-all-ip', 6, 60)) return;
    const body = await readBody(req);
    const key = String(body.key || '').trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });

    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });
    if (!await enforceRateLimit(req, res, 'reward-all-user', 2, 60, user.id)) return;

    const [collectionRows, claimedRows] = await Promise.all([getCollection(user.id), getMemberRewards(user.id)]);
    const owned = new Set(collectionRows.filter((row) => row.count > 0).map((row) => row.card_id));
    const claimed = new Set(claimedRows.map((row) => row.member));
    const byMember = new Map();
    for (const card of getCards()) {
      const list = byMember.get(card.member) || [];
      list.push(card.id);
      byMember.set(card.member, list);
    }

    const targets = [];
    for (const [member, cardIds] of byMember) {
      const reward = MEMBER_REWARDS[member] || 0;
      if (reward > 0 && !claimed.has(member) && cardIds.every((cardId) => owned.has(cardId))) {
        targets.push({ member, reward });
      }
    }
    if (!targets.length) return sendJson(res, 200, { ok: false, message: '받을 수 있는 도감 보상이 없습니다' });

    let points = user.points;
    let total = 0;
    const received = [];
    for (const target of targets) {
      const rows = await rpc('gacha_claim_reward', {
        p_user_id: user.id,
        p_member: target.member,
        p_reward: target.reward,
        p_ranking_bonus: 1000,
      });
      const result = rows?.[0];
      if (result?.claimed) {
        points = result.points;
        total += target.reward;
        received.push(target.member);
      }
    }
    return sendJson(res, 200, {
      ok: received.length > 0,
      points,
      total,
      claimed: received,
      message: received.length ? null : '받을 수 있는 도감 보상이 없습니다',
    });
  } catch (error) {
    return serverError(res, 'claim-all-rewards', error, '도감 보상 일괄 수령에 실패했습니다');
  }
};
