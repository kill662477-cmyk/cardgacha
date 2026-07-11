// POST /api/claim-reward {key, member} -> {ok, points, reward, member}
// 크루 멤버: member=멤버명 -> 해당 멤버 카드 전체 보유 시 MEMBER_REWARDS 1회 지급.
// 컬렉션: member="명예유스"/"암연시" -> 해당 collection 카드 전체 보유 시 COLLECTION_REWARDS 1회 지급.
// migration2(gacha_member_rewards) 실행 전에는 ok:false 로 graceful 응답.
const { sendJson, readBody } = require('../lib/http');
const {
  getCards, MEMBER_REWARDS, COLLECTION_REWARDS, COLLECTION_LABELS,
} = require('../lib/gacha');
const {
  getUserByKey, updateUser, getCollection, getMemberRewards, insertMemberReward,
} = require('../lib/supabase');

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

    const cards = getCards();

    // 대상 카드 + 보상액 결정 (컬렉션 단위 vs 크루 개별)
    let targetCards;
    let rewardAmount;
    const collectionKey = COLLECTION_LABELS[member];
    if (collectionKey) {
      // 명예유스/암연시: 해당 collection 카드 전부
      targetCards = cards.filter((c) => c.collection === collectionKey);
      rewardAmount = COLLECTION_REWARDS[collectionKey] || 0;
    } else {
      // 크루 개별: 멤버명 일치 카드. collection 카드는 개별 수령 불가.
      targetCards = cards.filter((c) => c.member === member);
      if (targetCards.some((c) => c.collection)) {
        return sendJson(res, 400, { error: '컬렉션 단위 보상입니다', ok: false });
      }
      rewardAmount = MEMBER_REWARDS[member] || 0;
    }
    if (!targetCards.length) return sendJson(res, 400, { error: '알 수 없는 멤버입니다' });

    // 보유 도감 대조
    const rows = await getCollection(user.id);
    const owned = new Set(rows.filter((r) => r.count > 0).map((r) => r.card_id));
    const complete = targetCards.every((c) => owned.has(c.id));
    if (!complete) return sendJson(res, 400, { error: '아직 도감을 완성하지 않았습니다', ok: false });

    // 수령 기록 (테이블 없으면 graceful)
    let already;
    try {
      already = await getMemberRewards(user.id);
    } catch (tblErr) {
      return sendJson(res, 200, { ok: false, reason: 'unavailable', message: '보상 기능 준비 중입니다' });
    }
    if (already.some((r) => r.member === member)) {
      return sendJson(res, 200, { ok: false, reason: 'claimed', message: '이미 수령한 보상입니다' });
    }

    // 지급: 수령 기록 먼저(중복 지급 방지, PK 충돌 시 실패) -> 포인트
    try {
      await insertMemberReward(user.id, member);
    } catch (dupErr) {
      return sendJson(res, 200, { ok: false, reason: 'claimed', message: '이미 수령한 보상입니다' });
    }
    const RANKING_BONUS = 1000;
    const updatePayload = { points: user.points + rewardAmount };
    if ('ranking_score' in user) {
      updatePayload.ranking_score = user.ranking_score + RANKING_BONUS;
    }
    const updated = await updateUser(user.id, updatePayload);

    return sendJson(res, 200, { ok: true, points: updated.points, reward: rewardAmount, member });
  } catch (e) {
    console.error('claim-reward error', e);
    return sendJson(res, 500, { error: '보상 수령 실패', detail: String(e.message || e) });
  }
};
