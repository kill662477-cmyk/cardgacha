// POST /api/register {nickname} -> {key, user}
const { sendJson, readBody } = require('../lib/http');
const { newKey } = require('../lib/gacha');
const { insertUser, getRecentAccountsCountByIp } = require('../lib/supabase');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const body = await readBody(req);
    const nickname = (body.nickname || '').toString().trim();
    if (!nickname) return sendJson(res, 400, { error: '닉네임을 입력하세요' });
    if (nickname.length > 40) return sendJson(res, 400, { error: '닉네임이 너무 깁니다' });

    const ip = req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '';
    
    // IP 기반 어뷰징 방지 (30분 이내 3개 이상 생성 금지)
    if (ip) {
      const recentCount = await getRecentAccountsCountByIp(ip, 30);
      if (recentCount >= 3) {
        return sendJson(res, 429, { error: '가입 시도가 너무 많습니다. 잠시 후 다시 시도해주세요.' });
      }
    }

    const key = newKey();
    const user = await insertUser(nickname, key, ip);
    return sendJson(res, 200, {
      key,
      user: {
        nickname: user.nickname,
        points: user.points,
        canAttend: true,
        streak: 'streak' in user ? user.streak : null,
      },
    });
  } catch (e) {
    console.error('register error', e);
    return sendJson(res, 500, { error: '가입 실패', detail: String(e.message || e) });
  }
};
