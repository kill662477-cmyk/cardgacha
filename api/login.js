// POST /api/login {key} -> {user}
const { sendJson, readBody } = require('../lib/http');
const { seoulToday } = require('../lib/gacha');
const { getUserByKey, updateUser } = require('../lib/supabase');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });

    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });

    // 로그인 시 IP 수집 (비동기 처리하여 응답 속도에 영향 안 주게 함)
    const ip = req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '';
    if (ip && user.last_ip !== ip) {
      updateUser(user.id, { last_ip: ip }).catch(e => console.error('ip update fail', e));
    }

    return sendJson(res, 200, {
      user: {
        nickname: user.nickname,
        points: user.points,
        canAttend: user.last_attend !== seoulToday(),
        streak: 'streak' in user ? user.streak : null,
      },
    });
  } catch (e) {
    console.error('login error', e);
    return sendJson(res, 500, { error: '로그인 실패', detail: String(e.message || e) });
  }
};
