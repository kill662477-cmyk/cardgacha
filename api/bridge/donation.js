const { readBody, sendJson } = require('../../lib/http');
const { rpc } = require('../../lib/supabase');
const { enforceRateLimit, serverError } = require('../../lib/security');
const { sessionFrom, tokenFrom } = require('../../lib/bridge-auth');

function value(input, max) {
  const text = String(input || '').trim();
  return text.length > 0 && text.length <= max ? text : '';
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'method not allowed' });
  const session = sessionFrom(req);
  const token = tokenFrom(req);
  if (!session?.soopId || token?.soopId !== session.soopId) return sendJson(res, 401, { error: '방송인 SOOP 연결이 필요합니다' });
  if (!await enforceRateLimit(req, res, 'soop-bridge-donation', 120, 60, session.nonce)) return;

  try {
    const body = await readBody(req);
    const eventId = value(body.eventId, 255);
    const senderSoopId = value(body.senderSoopId, 100);
    const recipientSoopId = value(body.recipientSoopId, 100);
    const amount = Number(body.amount);
    if (!eventId || !senderSoopId || !recipientSoopId || !Number.isSafeInteger(amount) || amount < 1 || amount > 100000) {
      return sendJson(res, 400, { error: '유효하지 않은 후원 이벤트입니다' });
    }
    if (recipientSoopId !== session.soopId) return sendJson(res, 403, { error: '연결한 방송국 후원만 처리할 수 있습니다' });

    const rows = await rpc('gacha_apply_soop_donation', {
      p_event_id: eventId,
      p_sender_soop_id: senderSoopId,
      p_recipient_soop_id: recipientSoopId,
      p_amount: amount,
    });
    const result = rows?.[0];
    if (!result) throw new Error('donation commit failed');
    return sendJson(res, 200, { ok: true, applied: Boolean(result.applied), amount });
  } catch (error) {
    return serverError(res, 'soop-donation', error, '후원 포인트 처리에 실패했습니다');
  }
};
