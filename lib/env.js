/*
 * .env.local 파서 (dotenv 미사용).
 * Vercel 에서는 process.env 가 이미 채워져 있으므로 파일이 없으면 그냥 넘어간다.
 * 로컬(dev-server)에서는 프로젝트 루트의 .env.local 을 읽어 process.env 에 주입.
 */
const fs = require('fs');
const path = require('path');

let loaded = false;
function loadEnv() {
  if (loaded) return;
  loaded = true;
  const file = path.resolve(__dirname, '..', '.env.local');
  if (!fs.existsSync(file)) return;
  const text = fs.readFileSync(file, 'utf8');
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let val = line.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (process.env[key] === undefined) process.env[key] = val;
  }
}

module.exports = { loadEnv };
