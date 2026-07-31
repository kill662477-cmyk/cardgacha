import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');

const css = await read('styles/renewal/main.css');
const html = await read('index.html');

// --- 하단 내비게이션 ---
// 회귀: 모바일 하단바가 grid-template-columns: repeat(9, 1fr) 로 고정돼 있었는데
// 메뉴가 10개로 늘면서 마지막 '미니게임'이 두 번째 줄로 밀려 화면 밖에 있었다.
// 열 개수를 고정하면 메뉴가 늘 때마다 같은 사고가 난다.
const navItemCount = (html.match(/class="nav-item[^"]*"[^>]*data-screen=/g) ?? []).length;
assert.ok(navItemCount >= 10, `nav-item 을 찾지 못했다 (${navItemCount}개)`);

const mobileNavRule = css.match(/\.side-nav nav \{[^}]*\}/g)?.find((rule) => rule.includes('grid-auto-flow') || rule.includes('repeat('));
assert.ok(mobileNavRule, '모바일 하단 내비 규칙을 찾지 못했다');
assert.doesNotMatch(
  css,
  /\.side-nav nav \{[^}]*grid-template-columns:\s*repeat\(\s*\d+/,
  '하단 내비 열 개수를 숫자로 고정하면 메뉴가 늘었을 때 마지막 항목이 화면 밖으로 밀린다',
);
assert.match(
  css,
  /\.side-nav nav \{[^}]*grid-auto-flow:\s*column[^}]*grid-auto-columns:\s*minmax\(0, 1fr\)/,
  '하단 내비는 메뉴 개수와 무관하게 한 줄에 균등 배치되어야 한다',
);

// --- 시스템 상태 패널(오류/재시도 화면) ---
// 회귀: 기본 규칙이 132px + minmax(260px, 1fr) 라 최소 476px 를 요구해
// 375px 화면에서 오른쪽이 잘려 나갔다. 모바일에서는 세로로 쌓아야 한다.
assert.match(
  css,
  /@media \(max-width: 900px\)[\s\S]*?\.system-state-panel \{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)/,
  '시스템 상태 패널은 모바일에서 1열로 쌓여야 한다',
);
assert.match(
  css,
  /@media \(max-width: 900px\)[\s\S]*?\.system-state-retry \{[^}]*width:\s*100%/,
  '재시도 버튼은 모바일에서 가로 폭을 채워야 한다',
);

// --- 상점 구매 버튼 줄 ---
// 회귀: .shop-buy-row 가 grid-template-columns: 1fr 1fr 로 2열 고정이었는데
// 카드팩 상품은 버튼이 3개(1개/10개/100개)라 100개 버튼이 다음 줄로 밀렸다.
// 모바일에서는 구매행 높이가 49px 로 고정이고 카드가 overflow:hidden 이라 잘려서 안 보였다.
assert.match(
  css,
  /\.shop-buy-row \{[^}]*grid-auto-flow:\s*column[^}]*grid-auto-columns:\s*minmax\(0, 1fr\)/,
  '구매 버튼 줄은 버튼 개수와 무관하게 한 줄에 배치되어야 한다',
);
assert.doesNotMatch(
  css,
  /\.shop-buy-row \{[^}]*grid-template-columns:\s*1fr 1fr/,
  '구매 버튼 열을 2개로 고정하면 100개 구매 버튼이 밀려 잘린다',
);
// 카드팩 상품에 100개 구매 버튼이 실제로 있어야 이 가드가 의미를 가진다.
const appSource = await read('src/renewal/app.js');
assert.match(appSource, /data-buy-count="100"/, '100개 구매 버튼이 없다');
const buyRowButtons = (appSource.match(/data-buy-count="\d+"/g) ?? []).length;
assert.ok(buyRowButtons >= 3, `카드팩 구매 버튼이 ${buyRowButtons}개뿐이다`);

// --- 강화 화면 EXP 포션 블록 ---
// 회귀: 포션 버튼 라벨이 좁은 칸에서 2줄로 접혀 버튼이 67px 로 부풀었고,
// 그만큼 밀린 '일괄 채우기' 버튼이 .enhance-focus 의 overflow:hidden 에 잘렸다.
assert.match(
  css,
  /@media \(max-width: 900px\)[\s\S]*?\.card-exp-potion-button span \{[^}]*white-space:\s*nowrap/,
  '포션 버튼 라벨이 접히면 버튼이 부풀어 아래 버튼을 밀어낸다',
);
assert.match(
  css,
  /@media \(max-width: 900px\)[\s\S]*?\.enhance-focus \{[^}]*overflow-y:\s*auto/,
  '세로 공간이 모자란 기기에서도 일괄 채우기 버튼에 닿을 수 있어야 한다',
);

// --- 상단바: 우편함 / 전광판 ---
// 회귀: 모바일에서 .currency-bar .icon-button 을 통째로 숨기면서 우편함까지 사라졌다.
// 우편함은 운영 안내와 보상이 도착하는 곳이라 반드시 닿을 수 있어야 한다.
assert.match(
  css,
  /@media \(max-width: 900px\)[\s\S]*?\.currency-bar #mailButton \{[^}]*display:\s*inline-grid/,
  '모바일에서 우편함 버튼이 보여야 한다',
);
assert.match(html, /id="mailButton"/, '우편함 버튼이 마크업에 있어야 한다');

// 회귀: 가로(전체화면)에서 전광판이 display:none 으로 통째로 숨겨져 있었다.
const landscapeBlock = css.match(/@media \(max-width: 900px\) and \(orientation: landscape\)[\s\S]*?\n\}/)?.[0] ?? '';
assert.ok(landscapeBlock, '가로 모드 미디어 블록을 찾지 못했다');
assert.doesNotMatch(
  landscapeBlock,
  /\.live-ticker \{[^}]*display:\s*none/,
  '가로 모드에서 전광판을 숨기면 안 된다',
);
assert.match(
  landscapeBlock,
  /\.live-ticker \{[^}]*display:\s*grid/,
  '가로 모드에서는 전광판을 상단바 같은 행에 배치해야 한다',
);

console.log(`mobile layout tests passed: ${navItemCount} nav items on one row, state panel stacks, ${buyRowButtons} buy buttons in one row`);
