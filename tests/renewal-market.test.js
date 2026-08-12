import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import cards from '../data/renewal-cards.json' with { type: 'json' };
import {
  MARKET_ASSETS,
  MARKET_PRODUCTS,
  MARKET_RULES,
  canAddMarketInvestment,
  marketFee,
  marketProductChangeRate,
  marketProductLabel,
  marketReturnRate,
  nextMarketProductPrice,
  nextMarketPrice,
  normalizeMarketQuantity,
} from '../src/renewal/market.js';
import { GAME_COMMAND_TYPES, createGameCommand, validateGameCommand } from '../src/renewal/service-contract.js';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const migration = await read('supabase/migrations/20260811090000_calms_market.sql');
const sql = migration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const dailyMigration = await read('supabase/migrations/20260811163000_market_daily_chart_kst.sql');
const dailySql = dailyMigration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const derivativesMigration = await read('supabase/migrations/20260812133000_market_leverage_inverse_and_1m_caps.sql');
const derivativesSql = derivativesMigration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const derivativeFloorMigration = await read('supabase/migrations/20260813084000_market_derivative_price_floor_1.sql');
const derivativeFloorSql = derivativeFloorMigration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const derivativeBuyGuardMigration = await read('supabase/migrations/20260813085400_block_derivative_buy_at_1p.sql');
const derivativeBuyGuardSql = derivativeBuyGuardMigration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const html = await read('index.html');
const css = await read('styles/renewal/main.css');
const controller = await read('src/renewal/minigame-controller.js');
const edge = await read('supabase/functions/game-command/index.ts');

assert.equal(MARKET_ASSETS.length, 14);
assert.deepEqual(MARKET_ASSETS.map(({ name }) => name), [
  '김윤환', '남덕선', '토마토', '지두두', '햇살', '찌킹', '치리',
  '소주양', '주하랑', '임조이', '비타밍', '먼진', '아리송이', '낭니',
]);
const catalogIds = new Set(cards.map(({ id }) => id));
MARKET_ASSETS.forEach(({ cardId }) => assert.equal(catalogIds.has(cardId), true, `${cardId} must exist`));
assert.equal(MARKET_RULES.totalInvestmentCap, 1_000_000);
assert.equal(MARKET_RULES.perAssetInvestmentCap, 1_000_000);
assert.equal(MARKET_RULES.feeRate, 0.015);
assert.equal(MARKET_RULES.hourlyChangeCap, 0.30);
assert.equal(MARKET_RULES.underlyingPriceFloor, 100);
assert.equal(MARKET_RULES.productPriceFloor, 1);
assert.equal(MARKET_RULES.historyResetsDaily, true);
assert.equal(MARKET_RULES.historyTimeZone, 'Asia/Seoul');
assert.equal(MARKET_PRODUCTS.length, 9);
assert.deepEqual(MARKET_PRODUCTS.map(({ label }) => label), [
  '일반', '레버리지 x2', '레버리지 x3', '레버리지 x4', '레버리지 x5',
  '인버스 x2', '인버스 x3', '인버스 x4', '인버스 x5',
]);
assert.equal(marketProductLabel('inverse', 4), '인버스 x4');
assert.ok(Math.abs(marketProductChangeRate(0.1, 'long', 3) - 0.3) < Number.EPSILON);
assert.equal(marketProductChangeRate(0.1, 'inverse', 5), -0.5);
assert.equal(nextMarketProductPrice(10_000, 0.1, { positionType: 'long', multiplier: 5, basePrice: 10_000 }), 15_000);
assert.equal(nextMarketProductPrice(10_000, 0.3, { positionType: 'inverse', multiplier: 5, basePrice: 10_000 }), 1);
assert.equal(nextMarketProductPrice(100, -0.1, { positionType: 'long', multiplier: 2, basePrice: 10_000 }), 80);
assert.equal(nextMarketProductPrice(100, -0.3, { positionType: 'long', multiplier: 1, basePrice: 10_000 }), 100);
assert.equal(marketFee(10_000), 150);
assert.equal(marketFee(1), 1);
assert.equal(marketReturnRate(1_500, 100_000), 1.5);
assert.equal(marketReturnRate(-1_500, 100_000), -1.5);
assert.equal(marketReturnRate(500, 0), 0);
assert.equal(nextMarketPrice(10_000, 0.80), 13_000);
assert.equal(nextMarketPrice(10_000, -0.80), 7_000);
assert.equal(normalizeMarketQuantity('3'), 3);
assert.equal(normalizeMarketQuantity('1.5'), 0);
assert.equal(canAddMarketInvestment({ totalCostBasis: 990_000, assetCostBasis: 990_000, purchaseCost: 10_000 }), true);
assert.equal(canAddMarketInvestment({ totalCostBasis: 990_001, assetCostBasis: 0, purchaseCost: 10_000 }), false);

const order = createGameCommand({
  type: GAME_COMMAND_TYPES.MARKET_TRADE,
  payload: { symbol: 'TMT', side: 'buy', quantity: 3, positionType: 'inverse', multiplier: 3 },
  expectedRevision: 4,
  idempotencyKey: 'market-order-0001',
  clientSentAt: 1_700_000_000_000,
});
assert.equal(validateGameCommand(order).valid, true);
assert.equal(validateGameCommand({ ...order, payload: { ...order.payload, side: 'hold' } }).valid, false);
assert.equal(validateGameCommand({ ...order, payload: { ...order.payload, quantity: 0 } }).valid, false);
assert.equal(validateGameCommand({ ...order, payload: { ...order.payload, multiplier: 1 } }).valid, false);

for (const table of [
  'gacha_s2_market_assets', 'gacha_s2_market_prices',
  'gacha_s2_market_holdings', 'gacha_s2_market_trades',
]) {
  assert.match(sql, new RegExp(`create table if not exists public\\.${table}`));
  assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`));
}
assert.match(sql, /pg_advisory_xact_lock\(hashtext\('gacha_s2_market:/);
assert.match(sql, /v_mode_roll < 0\.70/);
assert.match(sql, /v_mode_roll < 0\.95/);
assert.match(sql, /v_previous\.trend_remaining > 0/);
assert.match(sql, /v_previous\.price > v_average \* 1\.40/);
assert.match(sql, /greatest\(-0\.30, least\(0\.30, v_rate\)\)/);
assert.match(sql, /'feerate', 0\.015/);
assert.match(sql, /'totalinvestmentcap', 500000/);
assert.match(sql, /'perassetinvestmentcap', 500000/);
assert.match(sql, /v_total_basis \+ v_cost > 500000/);
assert.match(sql, /v_asset_basis \+ v_cost > 500000/);
assert.match(sql, /for update/);
assert.match(sql, /gacha_s2_idempotency/);
assert.match(sql, /gacha_s2_command_audit/);
assert.doesNotMatch(sql, /gacha_s2_minigame_daily/, 'market economy must stay outside minigame reward cap');
assert.match(sql, /gacha_s2_client_get_market_state\(\)/);
assert.match(sql, /gacha_s2_client_account_id\(\)/);
assert.match(dailySql, /date_trunc\('day', v_hour at time zone 'asia\/seoul'\) at time zone 'asia\/seoul'/);
assert.match(dailySql, /hour_at >= v_day_start/);
assert.match(dailySql, /'historystartsat'/);
assert.match(derivativesSql, /create table if not exists public\.gacha_s2_market_product_prices/);
assert.match(derivativesSql, /create table if not exists public\.gacha_s2_market_liquidations/);
assert.match(derivativesSql, /primary key \(user_id, symbol, position_type, multiplier\)/);
assert.match(derivativesSql, /'totalinvestmentcap', 1000000/);
assert.match(derivativesSql, /'perassetinvestmentcap', 1000000/);
assert.match(derivativesSql, /v_total_basis \+ v_cost > 1000000/);
assert.match(derivativesSql, /v_asset_basis \+ v_cost > 1000000/);
assert.match(derivativesSql, /gacha_s2_market_settle_liquidations/);
assert.match(derivativesSql, /1 - 1\.0 \/ v_holding\.multiplier/);
assert.match(derivativesSql, /1 \+ 1\.0 \/ v_holding\.multiplier/);
assert.match(derivativesSql, /position_type = 'inverse'/);
assert.match(derivativesSql, /p_position_type text/);
assert.match(derivativesSql, /p_multiplier integer/);
assert.match(derivativeFloorSql, /gacha_s2_market_product_prices_price_check check \(price >= 1\)/);
assert.match(derivativeFloorSql, /gacha_s2_market_trades_unit_price_check check \(unit_price >= 1\)/);
assert.match(derivativeFloorSql, /then 100 else 1 end/);
assert.match(derivativeBuyGuardSql, /new\.side = 'buy'/);
assert.match(derivativeBuyGuardSql, /new\.multiplier >= 2/);
assert.match(derivativeBuyGuardSql, /new\.unit_price <= 1/);
assert.match(derivativeBuyGuardSql, /market_product_buy_suspended/);

assert.match(html, /data-minigame-select="market"/);
assert.match(html, /id="marketShell"/);
assert.match(html, /id="marketBuyButton"/);
assert.match(html, /aria-label="오늘 시간별 가격 차트"/);
assert.match(html, /id="marketProductSelect"/);
assert.match(html, /레버리지 x5/);
assert.match(html, /인버스 x5/);
assert.match(html, /전체\/종목당 투자 원금 최대 1,000,000P/);
assert.match(css, /\.market-shell/);
assert.match(controller, /loadMarketState/);
assert.match(controller, /submitMarketTrade/);
assert.match(controller, /serverCommands\?\.marketTrade/);
assert.match(controller, /marketReturnRate\(unrealized, invested\)/);
assert.match(controller, /marketProductRiskText/);
assert.match(controller, /buySuspended/);
assert.match(controller, /1P에 도달한 레버리지·인버스 상품은 신규 매수할 수 없습니다/);
assert.match(controller, /positionType: product\.positionType/);
assert.match(controller, /오늘 · 1시간봉/);
assert.match(controller, /minigameScreen\.classList\.toggle\('market-mode', market\)/);
assert.match(css, /\.minigame-screen\.market-mode\s*\{[^}]*grid-template-columns:\s*200px/);
assert.match(css, /@media \(max-width: 900px\) and \(orientation: portrait\)[\s\S]*\.market-mode \.market-asset-list\s*\{[^}]*grid-auto-flow:\s*column/);
assert.match(css, /@media \(max-width: 900px\) and \(orientation: portrait\)[\s\S]*\.market-mode \.minigame-control\s*\{[^}]*grid-row:\s*3/);
assert.match(edge, /body\.kind === 'marketState'/);

console.log('renewal market tests passed: 14 assets, 9 products, forced liquidation, 1m caps, atomic real-P ledger');
