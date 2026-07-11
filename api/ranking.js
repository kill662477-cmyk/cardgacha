// GET /api/ranking -> { rankings: [{ nickname, score }] }
const { sendJson } = require('../lib/http');
const { REST, headers, sbFetch } = require('../lib/supabase');

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const rows = await sbFetch(
      `${REST}/gacha_users?select=nickname,ranking_score&nickname=not.eq.${encodeURIComponent('플로우검증봇')}&order=ranking_score.desc.nullslast&limit=50`,
      { headers: headers() }
    );
    res.setHeader('Cache-Control', 's-maxage=10, stale-while-revalidate=59');
    return sendJson(res, 200, { rankings: rows.map(r => ({ nickname: r.nickname, score: r.ranking_score || 0 })) });
  } catch (e) {
    console.error('ranking error', e);
    console.error('ranking error', e?.message || e);
    return sendJson(res, 500, { error: '랭킹 조회 실패' });
  }
};
