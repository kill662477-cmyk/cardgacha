import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { LIVE_TICKER_ENABLED } from '../src/renewal/config.js';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');

// --- 스위치 ---
// 전광판은 이 값 하나로만 켜고 끈다. 자동 복귀 없음.
assert.equal(typeof LIVE_TICKER_ENABLED, 'boolean', '전광판 스위치는 boolean 이어야 한다');

// --- 컨트롤러 배선 ---
const controller = await read('src/renewal/live-ticker-controller.js');
assert.match(controller, /LIVE_TICKER_ENABLED/, '컨트롤러가 스위치를 읽어야 한다');
assert.match(controller, /ticker\.hidden = true/, '꺼져 있으면 요소를 감춰야 한다');
assert.match(controller, /ticker\.hidden = false/, '켜면 다시 보여야 한다');

// 꺼진 상태에서 서버를 계속 두드리면 끈 의미가 없다. 폴링과 타이머 둘 다 막아야 한다.
assert.match(
  controller,
  /async function poll\(\)[\s\S]{0,160}?if \(!LIVE_TICKER_ENABLED\) return;/,
  '꺼져 있으면 폴링을 건너뛰어야 한다',
);
assert.match(
  controller,
  /async function start\(\)[\s\S]{0,200}?if \(!LIVE_TICKER_ENABLED\) return;/,
  '꺼져 있으면 폴링 타이머를 걸지 않아야 한다',
);

// --- CSS ---
// [hidden] 은 display 선언에 밀린다. 미디어쿼리의 display: grid 까지 이겨야 한다.
const css = await read('styles/renewal/main.css');
assert.match(
  css,
  /\.live-ticker\[hidden\] \{ display: none !important; \}/,
  'hidden 이 display 선언을 이기도록 규칙이 있어야 한다',
);

console.log(`live ticker switch tests passed: LIVE_TICKER_ENABLED = ${LIVE_TICKER_ENABLED}`);
