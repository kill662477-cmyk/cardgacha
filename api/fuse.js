// POST /api/fuse {key, cardIds:[3]}
// 동일 등급 카드 3장(각 카드 1장 보존, 초과분만) 소모 -> 확률 성공 시 한 단계 위 등급 랜덤 카드 1장.
// 실패 시 재료 소멸 + 위로 포인트. 판정/결과카드 전부 서버(secureRandom).
const { sendJson, readBody } = require('../lib/http');
const { RANK, FUSE_RATES, DISMANTLE_REFUND, cardById, resolveFuse } = require('../lib/gacha');
const { getUserByKey, getCollection, insertAnnouncements, rpc } = require('../lib/supabase');
const { enforceRateLimit, serverError } = require('../lib/security');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });

    const cardIds = Array.isArray(body.cardIds) ? body.cardIds.map((c) => (c || '').toString().trim()) : null;
    if (!cardIds || cardIds.length !== 3 || cardIds.some((id) => !id)) {
      return sendJson(res, 400, { error: '재료 카드 3장을 선택하세요' });
    }

    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });
    if (!await enforceRateLimit(req, res, 'fuse-user', 12, 60, user.id)) return;

    // 재료 검증: 모두 알려진 카드 + 동일 등급 + FUR 아님(합성 가능 등급)
    const mats = cardIds.map((id) => cardById(id));
    if (mats.some((c) => !c)) return sendJson(res, 400, { error: '알 수 없는 카드가 포함되어 있습니다' });
    const rarity = mats[0].rarity;
    if (mats.some((c) => c.rarity !== rarity)) return sendJson(res, 400, { error: '같은 등급 카드 3장만 합성할 수 있습니다' });
    if (FUSE_RATES[rarity] == null) return sendJson(res, 400, { error: '합성할 수 없는 등급입니다 (FUR은 최상위)' });

    // 보유 수량 조회 + 보존 규칙 검증(각 카드 1장 보존, 초과분만 재료)
    const owned = {};
    for (const row of await getCollection(user.id)) owned[row.card_id] = row.count;
    const used = {};
    for (const id of cardIds) used[id] = (used[id] || 0) + 1;
    const consume = [];
    for (const [id, useCount] of Object.entries(used)) {
      const have = owned[id] || 0;
      if (have - useCount < 1) {
        return sendJson(res, 400, { error: '각 카드 1장은 보존됩니다. 초과분만 재료로 쓸 수 있습니다' });
      }
      consume.push({ card_id: id, expected_count: have, new_count: have - useCount });
    }

    // 판정 (성공/실패 + 결과카드/위로보상 모두 서버에서 결정)
    const outcome = resolveFuse(rarity);
    if (!outcome) return sendJson(res, 400, { error: '합성할 수 없는 등급입니다' });

    let resultCardId = null;
    let pointsGain = 0;
    let scoreGain = 0;
    let isNew = false;
    if (outcome.success) {
      resultCardId = outcome.card.id;
      isNew = !(owned[resultCardId] > 0);
      // open-pack 과 동일하게 신규 카드는 분해가치만큼 랭킹 점수 가산
      scoreGain = isNew ? (DISMANTLE_REFUND[outcome.card.rarity] || 0) : 0;
    } else {
      pointsGain = outcome.consolation;
    }

    const rows = await rpc('gacha_fuse', {
      p_user_id: user.id,
      p_consume: consume,
      p_success: outcome.success,
      p_result_card_id: resultCardId,
      p_points_gain: pointsGain,
      p_score_gain: scoreGain,
    });
    const updated = rows?.[0];
    if (!updated) throw new Error('fuse commit failed');

    // 로컬 컬렉션 응답(분해와 동일 패턴): 재료 차감 반영 + 성공 시 결과카드 반영
    const collection = { ...owned };
    for (const item of consume) collection[item.card_id] = item.new_count;
    if (outcome.success) collection[resultCardId] = (collection[resultCardId] || 0) + 1;

    // 결과가 UR 이상이면 티커 공지(open-pack 패턴 재사용)
    if (outcome.success && RANK[outcome.card.rarity] >= RANK.UR) {
      try {
        await insertAnnouncements([{
          nickname: user.nickname, member: outcome.card.member,
          card_id: outcome.card.id, rarity: outcome.card.rarity,
        }]);
      } catch (announcementError) {
        console.error('fuse announcement insert failed', announcementError?.message || announcementError);
      }
    }

    if (outcome.success) {
      const c = outcome.card;
      // updated.serial: RPC가 발행한 결과카드 시리얼. migration8 전이면 undefined → graceful 생략.
      const card = { id: c.id, member: c.member, file: c.file, rarity: c.rarity, isNew };
      if (updated.serial != null) card.serial = updated.serial;
      return sendJson(res, 200, {
        success: true,
        card,
        rate: outcome.rate, points: updated.points, collection, rates: FUSE_RATES,
      });
    }
    return sendJson(res, 200, {
      success: false,
      consolation: outcome.consolation,
      rate: outcome.rate, points: updated.points, collection, rates: FUSE_RATES,
    });
  } catch (e) {
    if (e?.code === 'P0001') return sendJson(res, 409, { error: '카드 상태가 변경되었습니다. 다시 시도해주세요.' });
    return serverError(res, 'fuse', e, '합성에 실패했습니다');
  }
};
