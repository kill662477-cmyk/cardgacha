import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { SERVER_AUTHORITY_FIELDS } from '../src/renewal/state-schema.js';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');

// 회귀: 서버 스냅샷이 내려보내는 필드를 여기 선언하지 않으면
// validateGameState 가 "v2에 선언되지 않은 필드"로 거부해 로그인 자체가 막힌다.
assert.ok(
  SERVER_AUTHORITY_FIELDS.includes('advancedPackPity'),
  'advancedPackPity 가 서버 권한 필드에 선언돼야 한다',
);

// --- 서버 스냅샷 ---
const snapshot = await read('supabase/migrations/20260805214322_snapshot_advanced_pack_pity_progress.sql');
assert.match(snapshot, /'advancedPackPity', jsonb_build_object/, '스냅샷에 진행도가 실려야 한다');
assert.match(snapshot, /'spent'/, '사용 누적액을 내려야 한다');
assert.match(snapshot, /'threshold'/, '임계값을 내려야 한다');
assert.match(snapshot, /'granted'/, '지급 횟수를 내려야 한다');
// 임계값을 코드에 박으면 밸런스에서 바꿨을 때 표시가 어긋난다.
assert.match(
  snapshot,
  /guaranteedTraitRerollPoints'\)::bigint\s*\n?\s*from public\.gacha_s2_balance_versions/,
  '임계값은 밸런스 설정에서 읽어야 한다',
);
// 누적 행이 없는 신규 계정도 스냅샷이 깨지면 안 된다.
assert.match(snapshot, /coalesce\(\(\s*\n?\s*select pity\.spent_since_grant/, '행이 없으면 0 으로 내려야 한다');
// 기존 필드를 실수로 떨어뜨리면 클라이언트 상태가 통째로 깨진다.
for (const field of ['guildBuff', 'supportItems', 'formation', 'powerRanking', 'cardProgress']) {
  assert.ok(snapshot.includes(`'${field}'`), `스냅샷에서 ${field} 가 사라졌다`);
}

// --- 클라이언트 표시 ---
const app = await read('src/renewal/app.js');
assert.match(app, /function advancedPackPityMarkup\(\)/, '진행도 마크업 함수가 있어야 한다');
assert.match(app, /state\.advancedPackPity/, '서버 값을 그대로 읽어야 한다');
// 확정 지급이 꺼진 상태(임계값 0/없음)에서 0으로 나누거나 빈 막대를 그리면 안 된다.
assert.match(app, /if \(threshold <= 0\) return '';/, '임계값이 없으면 아무것도 그리지 않아야 한다');
// 고급팩에만 붙는다. 일반 보급팩에 붙으면 잘못된 안내가 된다.
assert.match(
  app,
  /productId === 'advancedSupport' \? advancedPackPityMarkup\(\) : ''/,
  '진행도는 고급 보급팩에만 표시해야 한다',
);

// --- CSS ---
const css = await read('styles/renewal/main.css');
assert.match(css, /\.shop-pity \{/, '진행도 스타일이 있어야 한다');
assert.match(css, /\.shop-pity-bar i \{/, '진행 막대 스타일이 있어야 한다');
// 회귀: 모바일 .shop-product 는 2행 고정 그리드라 블록을 그냥 넣으면 배치가 깨진다.
assert.match(
  css,
  /\.shop-product:has\(\.shop-pity\) \{ grid-template: 58px auto auto/,
  '모바일에서는 고급팩만 행을 하나 더 써야 한다',
);
assert.match(
  css,
  /\.shop-product:has\(\.shop-pity\) \.shop-buy-row \{ grid-row: 3; \}/,
  '모바일에서 구매 버튼 줄이 3행으로 내려가야 한다',
);

console.log('advanced pack pity progress tests passed: snapshot field, client markup, mobile layout');
