import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// 회귀: SSS 카드 선택권이 한 번 고르면 두 장이 써졌다.
// 성공 후에도 selectedCardSelectorCardId 와 확인 버튼이 살아 있어서, 결과창을 닫는
// 클릭이나 버튼에 남은 포커스에서 누른 엔터가 같은 카드로 곧바로 두 번째 장을 썼다.
// 2026-08-10 지급 직후 사용 계정 64명 중 61명이 30초 안에 두 번째 실행이 찍혔다.
const source = await readFile(new URL('../src/renewal/app.js', import.meta.url), 'utf8');

// 선택 상태를 비우는 함수가 있어야 한다.
assert.match(source, /function clearCardSelectorSelection\(\)/, '선택 상태를 비우는 함수가 있어야 한다');
const clearBody = source.slice(source.indexOf('function clearCardSelectorSelection()')).split(/\n}\s*\n/)[0];
assert.match(clearBody, /selectedCardSelectorItemId = null/, '아이템 선택을 비워야 한다');
assert.match(clearBody, /selectedCardSelectorCardId = null/, '카드 선택을 비워야 한다');
assert.match(clearBody, /cardSelectorConfirm\.disabled = true/, '확인 버튼을 잠가야 한다');

// 두 사용 경로(카드 선택권 / 특성 변경권) 모두 지켜야 한다.
for (const [fn, label] of [
  ['redeemSelectedCardSelector', '카드 선택권'],
  ['rerollSelectedCardTrait', '특성 변경권'],
]) {
  const start = source.indexOf(`async function ${fn}()`);
  assert.ok(start > 0, `${fn} 이 있어야 한다`);
  const body = source.slice(start, source.indexOf('\n}\n', start));

  // 창이 닫혀 있으면 사용자가 고르는 중이 아니다. 창 밖 입력은 무시해야 한다.
  assert.match(
    body,
    /if \(!elements\.cardSelectorDialog\?\.open\) return;/,
    `${label}: 선택 창이 닫혀 있으면 실행하면 안 된다`,
  );
  // 성공 경로마다 선택 상태를 비워야 한다. 원격/로컬 두 갈래가 있다.
  const closes = (body.match(/elements\.cardSelectorDialog\.close\(\);/g) ?? []).length;
  const clears = (body.match(/clearCardSelectorSelection\(\);/g) ?? []).length;
  assert.ok(closes > 0, `${label}: 성공 후 창을 닫아야 한다`);
  assert.equal(clears, closes, `${label}: 창을 닫는 곳마다 선택 상태를 비워야 한다`);
  // 잠금 순서가 뒤집히면 안 된다. 비우기 전에 렌더가 돌면 옛 선택이 다시 그려진다.
  assert.ok(
    body.indexOf('clearCardSelectorSelection();') < body.indexOf('renderShop();'),
    `${label}: 선택 상태를 비운 뒤에 다시 그려야 한다`,
  );
}

// 어떤 경로로 닫혀도(ESC, 배경 클릭, 닫기 버튼) 선택이 남으면 안 된다.
assert.match(
  source,
  /cardSelectorDialog\.addEventListener\('close', clearCardSelectorSelection\)/,
  '창이 닫히면 선택 상태를 비워야 한다',
);

// 확인 버튼은 여전히 하나의 진입점을 통해야 한다. 두 곳에서 직접 부르면 잠금이 갈린다.
assert.equal(
  (source.match(/cardSelectorConfirm\.addEventListener\('click'/g) ?? []).length,
  1,
  '확인 버튼 리스너는 하나여야 한다',
);

console.log('card selector guard tests passed: dialog-open guard, selection cleared on every close');
