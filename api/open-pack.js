// POST /api/open-pack {key, packId} -> {cards:[{...,isNew}], points}
const { sendJson, readBody } = require('../lib/http');
const { PACKS, openPack, RANK, DISMANTLE_REFUND } = require('../lib/gacha');
const { getUserByKey, updateUser, getCollectionCounts, upsertCollection, insertAnnouncements } = require('../lib/supabase');

const userLocks = new Set();

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    const packId = (body.packId || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });

    const pack = PACKS[packId];
    if (!pack) return sendJson(res, 400, { error: '잘못된 팩입니다' });

    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });

    if (userLocks.has(user.id)) {
      return sendJson(res, 429, { error: '처리 중입니다. 잠시 후 다시 시도해주세요.' });
    }
    userLocks.add(user.id);

    try {
      if (user.points < pack.price) {
        return sendJson(res, 400, { error: '포인트가 부족합니다', points: user.points });
      }

      // 1) 뽑기 (서버)
      const drawn = openPack(packId);

      // 2) 기존 보유 수량 조회 -> isNew 판정 & 누적
      const ids = drawn.map((c) => c.id);
      const existing = await getCollectionCounts(user.id, ids);
      const gain = {}; // card_id -> 이번에 뽑은 개수
      for (const id of ids) gain[id] = (gain[id] || 0) + 1;

      const upsertRows = Object.keys(gain).map((cardId) => ({
        user_id: user.id,
        card_id: cardId,
        count: (existing[cardId] || 0) + gain[cardId],
      }));

      // isNew: 이번 개봉 전 보유 0 이었던 카드 (같은 팩 내 첫 등장만 NEW)
      const seen = new Set();
      let newCardScore = 0;
      const resultCards = drawn.map((c) => {
        const wasNew = !existing[c.id] && !seen.has(c.id);
        seen.add(c.id);
        if (wasNew) {
          newCardScore += (DISMANTLE_REFUND[c.rarity] || 0);
        }
        return { id: c.id, member: c.member, file: c.file, rarity: c.rarity, isNew: wasNew };
      });

      const scoreGain = pack.price + newCardScore;

      // 3) 포인트 차감 + 컬렉션 갱신 + 랭킹 점수 갱신
      const updatePayload = { points: user.points - pack.price };
      if ('ranking_score' in user) {
        updatePayload.ranking_score = user.ranking_score + scoreGain;
      }
      const updated = await updateUser(user.id, updatePayload);
      await upsertCollection(upsertRows);

      // 3.5) UR 이상 레어 드랍 -> 전체 공지 기록 (best-effort)
      try {
        const rare = drawn
          .filter((c) => RANK[c.rarity] >= RANK.UR)
          .map((c) => ({ nickname: user.nickname, member: c.member, card_id: c.id, rarity: c.rarity }));
        if (rare.length) await insertAnnouncements(rare);
      } catch (annErr) {
        console.error('announcement insert failed (무시)', annErr.message);
      }

      return sendJson(res, 200, { cards: resultCards, points: updated.points });
    } finally {
      userLocks.delete(user.id);
    }
  } catch (e) {
    console.error('open-pack error', e);
    return sendJson(res, 500, { error: '개봉 실패', detail: String(e.message || e) });
  }
};
