/*
 * 로컬 개발 서버 (포트 3300). vercel dev 없이 정적 + api 를 서빙한다.
 * 의존성 0 (Node 내장 http/fs 만 사용). .env.local 은 lib/env 로 파싱.
 *   node scripts/dev-server.js
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const { loadEnv } = require('../lib/env');
loadEnv();

const ROOT = path.resolve(__dirname, '..');
const PORT = process.env.PORT || 3300;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.avif': 'image/avif',
  '.webp': 'image/webp',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webm': 'video/webm',
  '.mp4': 'video/mp4',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

// api 핸들러 매핑
const API = {
  '/api/register': require('../api/register'),
  '/api/login': require('../api/login'),
  '/api/attend': require('../api/attend'),
  '/api/open-pack': require('../api/open-pack'),
  '/api/collection': require('../api/collection'),
  '/api/cards': require('../api/cards'),
  '/api/announcements': require('../api/announcements'),
  '/api/dismantle': require('../api/dismantle'),
  '/api/claim-reward': require('../api/claim-reward'),
  '/api/public-config': require('../api/public-config'),
  '/api/ranking': require('../api/ranking'),
};

function serveStatic(req, res, urlPath) {
  let rel = decodeURIComponent(urlPath.split('?')[0]);
  if (rel === '/' || rel === '') rel = '/index.html';
  // 경로 이탈 방지
  const filePath = path.normalize(path.join(ROOT, rel));
  if (!filePath.startsWith(ROOT)) {
    res.statusCode = 403; res.end('forbidden'); return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.statusCode = 404;
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
      res.end('404 Not Found: ' + rel);
      return;
    }
    res.statusCode = 200;
    res.setHeader('Content-Type', MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream');
    res.end(data);
  });
}

const server = http.createServer((req, res) => {
  const urlPath = (req.url || '/').split('?')[0];
  const handler = API[urlPath];
  if (handler) {
    Promise.resolve(handler(req, res)).catch((e) => {
      console.error('handler crash', e);
      if (!res.headersSent) {
        res.statusCode = 500;
        res.end(JSON.stringify({ error: 'server error' }));
      }
    });
    return;
  }
  serveStatic(req, res, req.url);
});

server.listen(PORT, () => {
  console.log(`card-gacha dev server -> http://localhost:${PORT}`);
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL) {
    console.log('  ! .env.local 의 Supabase 값이 안 읽혔습니다. api 호출은 실패할 수 있어요.');
  }
});
