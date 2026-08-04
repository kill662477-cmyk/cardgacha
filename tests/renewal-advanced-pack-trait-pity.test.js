import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { ADVANCED_SUPPORT_PACK, SUPPORT_PACK, SUPPORT_ITEMS } from '../src/renewal/config.js';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');

// --- 설정 ---
const threshold = ADVANCED_SUPPORT_PACK.guaranteedTraitRerollPoints;
assert.equal(threshold, 3_000_000, '고급팩 확정 지급 임계값은 300만 포인트다');
assert.ok(Number.isInteger(threshold) && threshold > 0, '임계값은 양의 정수여야 한다');
assert.ok(SUPPORT_ITEMS.traitReroll, 'traitReroll 아이템 정의가 있어야 한다');

// 확정 지급은 고급팩 전용이다. 일반 보급팩에 임계값이 붙으면 안 된다.
assert.equal(
  SUPPORT_PACK.guaranteedTraitRerollPoints,
  undefined,
  '일반 보급팩은 확정 지급 대상이 아니다',
);

// 임계값이 팩 단가보다 훨씬 커야 매 구매마다 지급되는 사고가 안 난다.
assert.ok(
  threshold > ADVANCED_SUPPORT_PACK.tenPrice * 10,
  `임계값(${threshold})이 10연 가격(${ADVANCED_SUPPORT_PACK.tenPrice}) 대비 너무 낮다`,
);

// 두 획득 경로의 기대치. 10연 1회 = tenPrice 포인트에 10회 추첨.
// 300만 확정은 확률 추첨(1장당 500만 포인트)보다 후해서 확정이 주 획득 경로가 된다.
// 의도된 설정이므로 대소를 단정하지 않고, 실제 배율이 크게 벗어나면 잡히도록만 둔다.
const drawsPerPoint = 10 / ADVANCED_SUPPORT_PACK.tenPrice;
const randomPerPoint = drawsPerPoint * (ADVANCED_SUPPORT_PACK.items.traitReroll / 100);
const pityPerPoint = 1 / threshold;
const pointsPerRerollCombined = 1 / (randomPerPoint + pityPerPoint);
assert.ok(
  pointsPerRerollCombined > ADVANCED_SUPPORT_PACK.tenPrice * 50,
  `합산 획득 주기(${Math.round(pointsPerRerollCombined)}P)가 너무 짧아 특성변경권이 흔해진다`,
);
assert.ok(
  pointsPerRerollCombined < 10_000_000,
  `합산 획득 주기(${Math.round(pointsPerRerollCombined)}P)가 너무 길어 확정 지급이 무의미해진다`,
);

// --- 서버 RPC ---
const rpc = await read('supabase/migrations/20260804002819_advanced_pack_trait_reroll_pity.sql');
assert.match(rpc, /gacha_s2_advanced_pack_trait_pity/, '누적 테이블이 있어야 한다');
assert.match(rpc, /guaranteedTraitRerollPoints/, '임계값은 서버가 밸런스 설정에서 다시 읽어야 한다');
assert.match(rpc, /if v_pity_threshold > 0 then/, '임계값이 없으면 지급 로직을 건너뛰어야 한다');
assert.match(
  rpc,
  /spent_since_grant = spent_since_grant - \(v_pity_grants::bigint \* v_pity_threshold\)/,
  '지급한 만큼 누적액을 차감해야 반복 지급이 안 난다',
);
assert.match(rpc, /granted_count = granted_count \+ v_pity_grants/, '지급 장수를 기록해야 한다');
assert.match(rpc, /check \(spent_since_grant >= 0\)/, '누적액이 음수가 되면 안 된다');

// 회귀 가드: 확정 지급분을 v_results 에 넣으면 뽑기 결과창에 노출된다.
// 운영 방침상 인벤토리에만 조용히 들어가야 한다.
const pityBlockRaw = rpc.match(/if v_pity_threshold > 0 then[\s\S]*?\n  end if;/)?.[0] ?? '';
assert.ok(pityBlockRaw, '확정 지급 블록을 찾지 못했다');
// 주석에 v_results 를 언급하는 것까지 잡히면 안 되므로 주석을 걷어내고 실행 코드만 본다.
const pityBlock = pityBlockRaw.replace(/--[^\n]*/g, '');
assert.doesNotMatch(pityBlock, /v_results/, '확정 지급분은 뽑기 결과 목록에 넣지 않는다');
assert.doesNotMatch(pityBlock, /gacha_s2_support_draws/, '확정 지급분은 뽑기 기록에 넣지 않는다');
assert.match(pityBlock, /support_items, array\['traitReroll'\]/, '인벤토리에는 반영해야 한다');

// 응답 계약: ok:true 필수 필드가 그대로 남아 있어야 한다(과거 serverSeed 누락 사고).
for (const field of ['contractVersion', 'ok', 'commandId', 'idempotencyKey', 'revision', 'serverTime', 'serverSeed', 'snapshot', 'result']) {
  assert.ok(rpc.includes(`'${field}'`), `RPC 성공 응답에 ${field} 가 없다`);
}
assert.match(rpc, /IDEMPOTENCY_KEY_REUSED/, '멱등성 재사용 가드가 있어야 한다');
assert.match(rpc, /VERSION_CONFLICT/, '리비전 충돌 가드가 있어야 한다');
assert.doesNotMatch(rpc, /grant execute[\s\S]*to authenticated/, 'RPC 는 service_role 전용이어야 한다');

// --- 전 계정 지급 마이그레이션 ---
const grant = await read('supabase/migrations/20260804002645_grant_trait_reroll_all_accounts_20260803.sql');
assert.match(grant, /array\['traitReroll'\]/, '지급 대상 아이템이 traitReroll 이어야 한다');
assert.match(grant, /to_jsonb\(t\.before_count \+ 1\)/, '계정당 1장만 지급해야 한다');
assert.match(grant, /revision = p\.revision \+ 1/, '리비전을 올려야 스냅샷이 갱신된다');
assert.match(grant, /not exists/, '재실행해도 중복 지급되지 않아야 한다');
assert.match(grant, /coverage mismatch/, '전 계정 지급 여부를 검증해야 한다');

console.log(
  `advanced pack trait pity tests passed: guaranteed every ${threshold.toLocaleString()}P, `
  + `random every ${Math.round(1 / randomPerPoint).toLocaleString()}P, `
  + `combined every ${Math.round(pointsPerRerollCombined).toLocaleString()}P`,
);
