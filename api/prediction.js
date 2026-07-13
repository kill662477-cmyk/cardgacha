// POST /api/prediction {key, action:"status"|"vote", option?}
const { sendJson, readBody } = require('../lib/http');
const { enforceRateLimit, serverError } = require('../lib/security');
const { getUserByKey, REST, headers, sbFetch } = require('../lib/supabase');
const { CIVIL_WAR_EVENT, publicEvent } = require('../lib/prediction-event');

async function getEvent() {
  const rows = await sbFetch(
    `${REST}/gacha_prediction_events?id=eq.${encodeURIComponent(CIVIL_WAR_EVENT.id)}&select=*`,
    { headers: headers() }
  );
  return rows?.[0] || CIVIL_WAR_EVENT;
}

async function getVote(userId) {
  const rows = await sbFetch(
    `${REST}/gacha_prediction_votes?event_id=eq.${encodeURIComponent(CIVIL_WAR_EVENT.id)}&user_id=eq.${userId}&select=option,created_at`,
    { headers: headers() }
  );
  return rows?.[0] || null;
}

async function getVoteTally() {
  const rows = await sbFetch(
    `${REST}/gacha_prediction_votes?event_id=eq.${encodeURIComponent(CIVIL_WAR_EVENT.id)}&select=option`,
    { headers: headers() }
  );
  const counts = Object.fromEntries(CIVIL_WAR_EVENT.options.map(option => [option, 0]));
  for (const row of rows || []) {
    if (Object.hasOwn(counts, row.option)) counts[row.option] += 1;
  }
  return { total: Object.values(counts).reduce((sum, count) => sum + count, 0), counts };
}

async function status(userId) {
  const [event, vote, tally] = await Promise.all([getEvent(), getVote(userId), getVoteTally()]);
  return { event: publicEvent(event), vote, tally };
}

async function vote(userId, option) {
  const event = await getEvent();
  const view = publicEvent(event);
  if (view.settledAt) return { code: 400, body: { error: '이미 결과가 확정된 이벤트입니다' } };
  if (view.closed) return { code: 400, body: { error: '선택 마감 시간이 지났습니다' } };
  if (!view.options.includes(option)) return { code: 400, body: { error: '선택지를 확인하세요' } };

  try {
    await sbFetch(`${REST}/gacha_prediction_votes`, {
      method: 'POST',
      headers: headers({ Prefer: 'return=minimal' }),
      body: JSON.stringify({ event_id: view.id, user_id: userId, option }),
    });
  } catch (e) {
    if (e.status === 409 || e.code === '23505') {
      return { code: 409, body: { error: '이미 선택을 완료했습니다' } };
    }
    throw e;
  }
  return { code: 200, body: await status(userId) };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  try {
    if (!await enforceRateLimit(req, res, 'prediction-ip', 40, 60)) return;
    const body = await readBody(req);
    const key = (body.key || '').toString().trim();
    const action = (body.action || 'status').toString();
    if (!key) return sendJson(res, 400, { error: 'key를 입력하세요' });
    const user = await getUserByKey(key);
    if (!user) return sendJson(res, 404, { error: '존재하지 않는 key입니다' });

    if (action === 'status') {
      const payload = await status(user.id);
      payload.points = user.points;
      return sendJson(res, 200, payload);
    }
    if (action === 'vote') {
      if (!await enforceRateLimit(req, res, 'prediction-vote-user', 6, 60, user.id)) return;
      const result = await vote(user.id, (body.option || '').toString().trim());
      return sendJson(res, result.code, result.body);
    }
    return sendJson(res, 400, { error: '알 수 없는 요청입니다' });
  } catch (e) {
    return serverError(res, 'prediction', e, '예측 이벤트 처리에 실패했습니다. 마이그레이션 적용 여부를 확인하세요.');
  }
};
