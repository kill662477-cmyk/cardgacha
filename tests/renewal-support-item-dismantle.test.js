import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  PACKS,
  SUPPORT_ITEMS,
  SUPPORT_ITEM_DISMANTLE,
  SUPPORT_PACK,
  canDismantleSupportItem,
  supportItemDismantleValue,
} from '../src/renewal/config.js';
import { GAME_COMMAND_TYPES, SUPPORT_ITEM_DISMANTLE_MAX_COUNT, validateGameCommand } from '../src/renewal/service-contract.js';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');

// --- 환급 단가가 설계식과 일치하는지 ---
// 기본식: round(basis / 출현확률). 교환권만 팩 정가 * packPriceShare 로 상한.
const TICKET_PACKS = { generalTicket: 'general', eliteTicket: 'elite', raceTicket: 'race', premiumTicket: 'premium' };
const { basis, packPriceShare, values } = SUPPORT_ITEM_DISMANTLE;

for (const [itemId, rate] of Object.entries(SUPPORT_PACK.items)) {
  const derived = Math.round(basis / rate);
  const packKey = TICKET_PACKS[itemId];
  const expected = packKey ? Math.min(derived, Math.round(PACKS[packKey].price * packPriceShare)) : derived;
  assert.equal(values[itemId], expected, `${itemId} 환급 단가가 설계식과 다르다`);
}

// 교환권 분해가 팩 구매보다 이득이면 안 된다. 상한을 두는 이유가 이것이다.
for (const [itemId, packKey] of Object.entries(TICKET_PACKS)) {
  assert.ok(
    values[itemId] < PACKS[packKey].price,
    `${itemId} 분해 환급(${values[itemId]}P)이 ${packKey} 팩 정가(${PACKS[packKey].price}P) 이상이면 분해가 구매보다 이득이 된다`,
  );
}

// 기대 환급률: 보급팩 1회를 까서 나온 아이템을 그대로 분해했을 때 회수되는 비율.
// 100% 를 넘으면 무한 포인트 루프가 된다. 여유를 크게 두고 상한을 잠근다.
const expectedRefund = Object.entries(SUPPORT_PACK.items)
  .reduce((sum, [itemId, rate]) => sum + (rate / 100) * values[itemId], 0);
assert.ok(
  expectedRefund < SUPPORT_PACK.price * 0.5,
  `기대 환급 ${expectedRefund.toFixed(1)}P 가 보급팩 가격 ${SUPPORT_PACK.price}P 의 50% 이상이다`,
);
assert.ok(expectedRefund > 0, '기대 환급이 0 이면 분해 기능이 무의미하다');

// 확률이 낮을수록 환급이 커야 한다(교환권 상한 대상 제외).
const curved = Object.entries(SUPPORT_PACK.items).filter(([itemId]) => !TICKET_PACKS[itemId]);
for (const [aId, aRate] of curved) {
  for (const [bId, bRate] of curved) {
    if (aRate >= bRate) continue;
    assert.ok(values[aId] >= values[bId], `${aId}(${aRate}%) 환급이 ${bId}(${bRate}%) 보다 커야 한다`);
  }
}

// --- 분해 대상 판정 ---
// 선택권은 보급팩 확률이 없어 기준가를 만들 수 없다. 분해 불가여야 한다.
assert.equal(canDismantleSupportItem('ssCardSelector'), false, 'SS 선택권은 분해 대상이 아니어야 한다');
assert.equal(canDismantleSupportItem('sssCardSelector'), false, 'SSS 선택권은 분해 대상이 아니어야 한다');
assert.equal(supportItemDismantleValue('ssCardSelector'), 0);
assert.equal(canDismantleSupportItem('energySmall'), true);
// values 의 모든 키는 실재하는 보급품이어야 한다(오타 방지).
for (const itemId of Object.keys(values)) {
  assert.ok(SUPPORT_ITEMS[itemId], `${itemId} 는 SUPPORT_ITEMS 에 없는 아이템이다`);
  assert.ok(Number.isInteger(values[itemId]) && values[itemId] > 0, `${itemId} 환급 단가는 양의 정수여야 한다`);
}

// --- 커맨드 계약 ---
const baseCommand = {
  contractVersion: 1,
  commandId: 'dismantle-support-1234',
  idempotencyKey: 'dismantle-support-1234',
  expectedRevision: 3,
  clientSentAt: 1_770_000_000_000,
  type: GAME_COMMAND_TYPES.DISMANTLE_SUPPORT_ITEM,
};
assert.equal(
  validateGameCommand({ ...baseCommand, payload: { itemId: 'energySmall', count: 2 } }).valid,
  true,
  '정상 분해 요청은 통과해야 한다',
);
assert.equal(
  validateGameCommand({ ...baseCommand, payload: { itemId: 'energySmall', count: 0 } }).valid,
  false,
  'count 0 은 거부해야 한다',
);
assert.equal(
  validateGameCommand({ ...baseCommand, payload: { itemId: 'energySmall', count: 1.5 } }).valid,
  false,
  '정수가 아닌 count 는 거부해야 한다',
);
// 회귀: 상한을 999 로 잡았다가 보유 1,000개 이상인 유저의 전량 분해가 전부 거부됐다.
// 실제 최대 보유량이 22,947 개였다.
assert.ok(SUPPORT_ITEM_DISMANTLE_MAX_COUNT >= 30000, '수량 상한이 실제 보유량을 감당하지 못한다');
assert.equal(
  validateGameCommand({ ...baseCommand, payload: { itemId: 'energySmall', count: 22947 } }).valid,
  true,
  '실제 보유 최대치(22,947개) 전량 분해가 통과해야 한다',
);
assert.equal(
  validateGameCommand({ ...baseCommand, payload: { itemId: 'energySmall', count: SUPPORT_ITEM_DISMANTLE_MAX_COUNT + 1 } }).valid,
  false,
  '상한 초과는 거부해야 한다',
);
// 최대 단가 * 최대 수량이 정수 범위를 넘으면 포인트가 깨진다.
assert.ok(
  Math.max(...Object.values(values)) * SUPPORT_ITEM_DISMANTLE_MAX_COUNT < 2_147_483_647,
  '최대 환급액이 integer 범위를 넘는다',
);
assert.equal(
  validateGameCommand({ ...baseCommand, payload: { itemId: 'energySmall', count: 1, sneak: 1 } }).valid,
  false,
  'allowedFields 밖 필드는 거부해야 한다',
);

// --- 서버 라우팅 ---
const router = await read('src/renewal/server-command-router.js');
assert.match(router, /DISMANTLE_SUPPORT_ITEM\]: 'gacha_s2_dismantle_support_item'/);
assert.match(router, /p_item_id: payload\.itemId, p_count: payload\.count/);

// --- 서버 RPC 가드 ---
const rpc = await read('supabase/migrations/20260731010000_dismantle_support_item.sql');
assert.match(rpc, /supportItemDismantle'->'values'->>p_item_id/, '환급 단가는 서버가 밸런스 설정에서 다시 읽어야 한다');
assert.match(rpc, /if v_unit_points is null or v_unit_points <= 0 then/, '목록에 없는 아이템은 서버가 거부해야 한다');
assert.match(rpc, /if v_owned < p_count then/, '보유 수량 검사가 있어야 한다');
assert.match(rpc, /p_count > 100000 then/, 'RPC 수량 상한이 계약 상한과 같아야 한다');
assert.match(rpc, /revision = revision \+ 1/, '리비전을 올려야 한다');
// 회귀: serverSeed 를 빼먹었더니 validateGameResponse 가 성공 응답을 거부해
// 서버는 커밋된 채로 화면만 "요청 처리 실패"가 떴다(아이템은 사라지고 UI 는 실패).
assert.match(rpc, /'serverSeed', v_seed/, '성공 응답에 serverSeed 가 있어야 한다');
assert.match(rpc, /v_seed := public\.gacha_s2_new_seed\(\)/, 'serverSeed 는 서버가 생성해야 한다');
assert.match(rpc, /IDEMPOTENCY_KEY_REUSED/, '멱등성 재사용 가드가 있어야 한다');
assert.match(rpc, /VERSION_CONFLICT/, '리비전 충돌 가드가 있어야 한다');
assert.doesNotMatch(rpc, /grant execute[\s\S]*to authenticated/, 'RPC 는 service_role 전용이어야 한다');

// validateGameResponse 가 ok:true 에 요구하는 필드는 RPC 응답에 전부 있어야 한다.
for (const field of ['contractVersion', 'ok', 'commandId', 'idempotencyKey', 'revision', 'serverTime', 'serverSeed', 'snapshot', 'result']) {
  assert.ok(rpc.includes(`'${field}'`), `RPC 성공 응답에 ${field} 가 없다`);
}

// 밸런스 카탈로그에 분해 단가가 실려야 서버가 읽을 수 있다.
const catalogBuilder = await read('scripts/build-renewal-database-catalog.js');
assert.match(catalogBuilder, /supportItemDismantle: SUPPORT_ITEM_DISMANTLE/);

// --- UI ---
const app = await read('src/renewal/app.js');
assert.match(app, /data-dismantle-shop-item="\$\{itemId\}"/, '인벤토리 행에 분해 버튼이 있어야 한다');
assert.match(app, /canDismantleSupportItem\(itemId\)/, '분해 불가 아이템에는 버튼을 그리면 안 된다');
assert.match(
  app,
  /async function dismantleShopItem[\s\S]{0,900}?window\.confirm\([\s\S]{0,400}?executeServerCommand\(GAME_COMMAND_TYPES\.DISMANTLE_SUPPORT_ITEM/,
  '분해는 confirm 통과 후에만 커맨드를 보내야 한다',
);
assert.match(app, /dismantleShopItem\(dismantleButton\.dataset\.dismantleShopItem\)/, '분해 버튼 클릭이 연결돼야 한다');

const css = await read('styles/renewal/main.css');
assert.match(css, /\.shop-item-action\.dismantle/, '분해 버튼은 사용 버튼과 시각적으로 구분돼야 한다');

console.log(
  `support item dismantle tests passed: ${Object.keys(values).length} items, `
  + `expected refund ${expectedRefund.toFixed(1)}P / ${SUPPORT_PACK.price}P pack `
  + `(${(expectedRefund / SUPPORT_PACK.price * 100).toFixed(1)}%)`,
);
