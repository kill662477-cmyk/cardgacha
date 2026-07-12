const { sendJson } = require('../../lib/http');
const { sessionFrom, tokenFrom } = require('../../lib/bridge-auth');

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method not allowed' });
  const session = sessionFrom(req);
  const token = tokenFrom(req);
  const connected = Boolean(session?.soopId && token?.soopId === session.soopId);
  return sendJson(res, 200, { authenticated: Boolean(session), connected, soopId: session?.soopId || '' });
};
