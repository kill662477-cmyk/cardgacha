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

console.log(`mobile layout tests passed: ${navItemCount} nav items on one row, state panel stacks under 900px`);
