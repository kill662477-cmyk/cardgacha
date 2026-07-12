// GET /api/ranking -> top 50; POST /api/ranking {key} -> top 50 + my rank
const { sendJson, readBody } = require('../lib/http');
const { REST, headers, sbFetch, getUserByKey, rpc } = require('../lib/supabase');

const BOT_NICKNAME = '플로우검증봇';

module.exports = async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    if (req.method === 'GET') {
      const rows = await sbFetch(
        `${REST}/gacha_users?select=nickname,ranking_score&nickname=not.eq.${encodeURIComponent(BOT_NICKNAME)}` +
          '&order=ranking_score.desc.nullslast,id.asc&limit=50',
        { headers: headers() }
      );
      res.setHeader('Cache-Control', 's-maxage=10, stale-while-revalidate=59');
      return sendJson(res, 200, {
        rankings: rows.map((row, index) => ({ rank: index + 1, nickname: row.nickname, score: row.ranking_score || 0 })),
      });
    }

    const body = await readBody(req);
    const key = String(body.key || '').trim();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });
    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });

    const rows = await rpc('gacha_get_ranking', { p_user_id: user.id });
    const result = rows?.[0];
    if (!result) return sendJson(res, 404, { error: '랭킹 정보를 찾을 수 없습니다' });
    return sendJson(res, 200, {
      rankings: Array.isArray(result.rankings) ? result.rankings : [],
      me: { rank: result.my_rank, nickname: result.my_nickname, score: result.my_score || 0 },
    });
  } catch (e) {
    console.error('ranking error', e?.message || e);
    return sendJson(res, 500, { error: '랭킹 조회 실패' });
  }
};
