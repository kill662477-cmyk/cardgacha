/*
 * 서버리스/로컬 공용 HTTP 헬퍼.
 * Vercel 은 req.body 를 자동 파싱하기도 하지만, 로컬 dev-server 는 아니므로
 * 두 경우 모두 안전하게 body 를 읽는다.
 */
function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  if (!res.getHeader('Cache-Control')) res.setHeader('Cache-Control', 'no-store');
  res.end(body);
}

async function readBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string' && req.body) {
    try { return JSON.parse(req.body); } catch (e) { return {}; }
  }
  return new Promise((resolve) => {
    let data = '';
    let size = 0;
    let tooLarge = false;
    req.on('data', (c) => {
      size += c.length;
      if (size > 16 * 1024) {
        tooLarge = true;
        return;
      }
      data += c;
    });
    req.on('end', () => {
      if (tooLarge) return resolve({});
      if (!data) return resolve({});
      try { resolve(JSON.parse(data)); } catch (e) { resolve({}); }
    });
    req.on('error', () => resolve({}));
  });
}

function getQuery(req) {
  const url = req.url || '';
  const qIndex = url.indexOf('?');
  const out = {};
  if (qIndex === -1) return out;
  const qs = url.slice(qIndex + 1);
  for (const pair of qs.split('&')) {
    if (!pair) continue;
    const [k, v] = pair.split('=');
    out[decodeURIComponent(k)] = decodeURIComponent((v || '').replace(/\+/g, ' '));
  }
  return out;
}

module.exports = { sendJson, readBody, getQuery };
