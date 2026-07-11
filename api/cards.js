// GET /api/cards -> cards.json 전체 (등급 포함)
const { sendJson } = require('../lib/http');
const { getCards } = require('../lib/gacha');

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    const cards = getCards();
    res.setHeader('Cache-Control', 'public, max-age=300');
    return sendJson(res, 200, { cards });
  } catch (e) {
    console.error('cards error', e);
    console.error('cards error', e?.message || e);
    return sendJson(res, 500, { error: '카드 목록 조회 실패' });
  }
};
