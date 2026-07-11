// POST /api/open-pack {key, packId}
const { sendJson, readBody } = require('../lib/http');
const { PACKS, openPack, RANK, DISMANTLE_REFUND } = require('../lib/gacha');
const { getUserByKey, getCollectionCounts, insertAnnouncements, rpc } = require('../lib/supabase');
const { enforceRateLimit, serverError } = require('../lib/security');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    if (!await enforceRateLimit(req, res, 'open-ip', 30, 60)) return;
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    const packId = (body.packId || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });
    const pack = PACKS[packId];
    if (!pack) return sendJson(res, 400, { error: '잘못된 팩입니다' });

    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });
    if (!await enforceRateLimit(req, res, 'open-user', 12, 60, user.id)) return;

    const drawn = openPack(packId);
    const ids = drawn.map((c) => c.id);
    const existing = await getCollectionCounts(user.id, ids);
    const gain = {};
    for (const id of ids) gain[id] = (gain[id] || 0) + 1;

    const seen = new Set();
    let newCardScore = 0;
    const cards = drawn.map((c) => {
      const isNew = !existing[c.id] && !seen.has(c.id);
      seen.add(c.id);
      if (isNew) newCardScore += DISMANTLE_REFUND[c.rarity] || 0;
      return { id: c.id, member: c.member, file: c.file, rarity: c.rarity, isNew };
    });

    const committed = await rpc('gacha_open_pack', {
      p_user_id: user.id,
      p_price: pack.price,
      p_score_gain: pack.price + newCardScore,
      p_gains: gain,
    });
    const updated = committed?.[0];
    if (!updated) throw new Error('pack commit failed');

    try {
      const rare = drawn
        .filter((c) => RANK[c.rarity] >= RANK.UR)
        .map((c) => ({ nickname: user.nickname, member: c.member, card_id: c.id, rarity: c.rarity }));
      if (rare.length) await insertAnnouncements(rare);
    } catch (announcementError) {
      console.error('announcement insert failed', announcementError?.message || announcementError);
    }

    return sendJson(res, 200, { cards, points: updated.points });
  } catch (e) {
    if (e?.code === 'P0001') return sendJson(res, 409, { error: '포인트 상태가 변경되었습니다. 다시 시도해주세요.' });
    return serverError(res, 'open-pack', e, '개봉에 실패했습니다');
  }
};
