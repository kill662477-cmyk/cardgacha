// POST /api/attend {key}
const { sendJson, readBody } = require('../lib/http');
const { seoulToday } = require('../lib/gacha');
const { getUserByKey, rpc } = require('../lib/supabase');
const { enforceRateLimit, serverError } = require('../lib/security');

const ATTEND_BASE = 400;
const ATTEND_STREAK_BONUS = 800;
const NEWBIE_BONUS = 100;

function seoulYesterday() {
  return new Date(Date.now() + 9 * 3600 * 1000 - 24 * 3600 * 1000).toISOString().slice(0, 10);
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });
    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });
    if (!await enforceRateLimit(req, res, 'attend-user', 4, 60, user.id)) return;

    const rows = await rpc('gacha_claim_attendance', {
      p_user_id: user.id,
      p_today: seoulToday(),
      p_yesterday: seoulYesterday(),
      p_base: ATTEND_BASE,
      p_streak_bonus: ATTEND_STREAK_BONUS,
      p_newbie_bonus: NEWBIE_BONUS,
    });
    const result = rows?.[0];
    if (!result) throw new Error('attendance commit failed');
    return sendJson(res, 200, result.attended
      ? result
      : { points: result.points, attended: false, streak: result.streak, message: '오늘은 이미 출석했습니다' });
  } catch (e) {
    return serverError(res, 'attend', e, '출석 처리에 실패했습니다');
  }
};
