// POST /api/attend {key} -> {points, attended, bonus, streak, nextBonusIn}
const { sendJson, readBody } = require('../lib/http');
const { seoulToday } = require('../lib/gacha');
const { getUserByKey, updateUser } = require('../lib/supabase');

const ATTEND_BASE = 400;
const ATTEND_STREAK_BONUS = 800; // 7의 배수 되는 날
const NEWBIE_BONUS = 100;        // 가입 7일 이내

// seoulToday 와 동일 규칙으로 "어제" 날짜(YYYY-MM-DD)
function seoulYesterday() {
  const seoul = new Date(Date.now() + 9 * 3600 * 1000 - 24 * 3600 * 1000);
  return seoul.toISOString().slice(0, 10);
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });

    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });

    const today = seoulToday();
    if (user.last_attend === today) {
      return sendJson(res, 200, {
        points: user.points,
        attended: false,
        streak: 'streak' in user ? user.streak : null,
        message: '오늘은 이미 출석했습니다',
      });
    }

    // migration2(streak 컬럼) 실행 전에는 기존 방식(+200 고정)으로 안전 폴백
    const streakSupported = 'streak' in user;

    if (!streakSupported) {
      const updated = await updateUser(user.id, {
        points: user.points + ATTEND_BASE,
        last_attend: today,
      });
      return sendJson(res, 200, {
        points: updated.points,
        attended: true,
        bonus: ATTEND_BASE,
        streak: null,
      });
    }

    // 연속 출석 계산
    const newStreak = user.last_attend === seoulYesterday() ? (user.streak || 0) + 1 : 1;

    let bonus = newStreak % 7 === 0 ? ATTEND_STREAK_BONUS : ATTEND_BASE;
    let newbie = false;
    if (user.created_at) {
      const ageMs = Date.now() - new Date(user.created_at).getTime();
      if (ageMs <= 7 * 24 * 3600 * 1000) { bonus += NEWBIE_BONUS; newbie = true; }
    }

    const updated = await updateUser(user.id, {
      points: user.points + bonus,
      last_attend: today,
      streak: newStreak,
    });

    return sendJson(res, 200, {
      points: updated.points,
      attended: true,
      bonus,
      streak: newStreak,
      newbie,
      nextBonusIn: (7 - (newStreak % 7)) % 7 || 7, // 다음 7일 보너스까지 남은 일수
    });
  } catch (e) {
    console.error('attend error', e);
    return sendJson(res, 500, { error: '출석 실패', detail: String(e.message || e) });
  }
};
