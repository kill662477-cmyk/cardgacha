import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import cards from '../data/renewal-cards.json' with { type: 'json' };
import {
  MARKET_ASSETS,
  MARKET_PRODUCTS,
  MARKET_RULES,
  canAddMarketInvestment,
  isMarketProductBuySuspended,
  marketFee,
  marketHoldings,
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
const derivativeUpperCapMigration = await read('supabase/migrations/20260813170000_market_derivative_upper_cap_fix.sql');
const derivativeUpperCapSql = derivativeUpperCapMigration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const floorRecoveryMigration = await read('supabase/migrations/20260813091000_recover_market_100p_floor_profit.sql');
const floorRecoverySql = floorRecoveryMigration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const floorRecoveryCorrectionMigration = await read('supabase/migrations/20260813092500_correct_market_floor_recovery_qualification.sql');
const floorRecoveryCorrectionSql = floorRecoveryCorrectionMigration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const marketCompensationMigration = await read('supabase/migrations/20260813094000_market_bug_global_compensation_500k.sql');
const marketCompensationSql = marketCompensationMigration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const lowPriceRecoveryMigration = await read('supabase/migrations/20260813101600_market_low_price_recovery_guard.sql');
const lowPriceRecoverySql = lowPriceRecoveryMigration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const vitamingNextLimitDownMigration = await read('supabase/migrations/20260813221500_schedule_vitaming_2300_limit_down_tick.sql');
const vitamingNextLimitDownSql = vitamingNextLimitDownMigration.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
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
assert.equal(MARKET_RULES.productPriceCeiling, 2_000_000_000);
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
assert.equal(nextMarketProductPrice(165_000, 0.1, { positionType: 'long', multiplier: 2, basePrice: 16_500 }), 198_000);
assert.equal(nextMarketProductPrice(165_000, 0.1, { positionType: 'long', multiplier: 1, basePrice: 16_500 }), 165_000);
assert.equal(isMarketProductBuySuspended(1, { positionType: 'long', multiplier: 2, basePrice: 16_500 }), true);
assert.equal(isMarketProductBuySuspended(165_000, { positionType: 'long', multiplier: 2, basePrice: 16_500 }), true);
assert.equal(isMarketProductBuySuspended(198_000, { positionType: 'long', multiplier: 2, basePrice: 16_500 }), false);
assert.equal(marketFee(10_000), 150);
assert.equal(marketFee(1), 1);
assert.equal(marketReturnRate(1_500, 100_000), 1.5);
assert.equal(marketReturnRate(-1_500, 100_000), -1.5);
assert.equal(marketReturnRate(500, 0), 0);
assert.deepEqual(marketHoldings([
  {
    symbol: 'TMT',
    name: '토마토',
    positions: [
      { positionType: 'long', multiplier: 1, quantity: 3, costBasis: 30_000, marketValue: 36_000, unrealizedPnl: 6_000 },
      { positionType: 'inverse', multiplier: 2, quantity: 4, costBasis: 20_000, marketValue: 40_000, unrealizedPnl: 20_000 },
      { positionType: 'long', multiplier: 3, quantity: 0, costBasis: 0, marketValue: 0, unrealizedPnl: 0 },
    ],
  },
]), [
  { symbol: 'TMT', name: '토마토', productKey: 'inverse:2', productLabel: '인버스 x2', quantity: 4, costBasis: 20_000, marketValue: 40_000, unrealizedPnl: 20_000 },
  { symbol: 'TMT', name: '토마토', productKey: 'long:1', productLabel: '일반', quantity: 3, costBasis: 30_000, marketValue: 36_000, unrealizedPnl: 6_000 },
]);
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
assert.match(derivativeUpperCapSql, /else 2000000000 end/);
assert.match(derivativeUpperCapSql, /new\.unit_price >= 2000000000/);
assert.match(derivativeUpperCapSql, /select asset\.base_price \* 10 into v_legacy_cap/);
assert.match(derivativeUpperCapSql, /new\.unit_price = v_legacy_cap/);
assert.match(derivativeUpperCapSql, /market_derivative_upper_cap_fix_guard_failed/);
assert.match(floorRecoverySql, /create table if not exists public\.gacha_s2_market_floor_recoveries/);
assert.match(floorRecoverySql, /trade\.unit_price = 100|v_event\.unit_price = 100/);
assert.match(floorRecoverySql, /realized_floor_profit/);
assert.match(floorRecoverySql, /unrealized_floor_profit/);
assert.match(floorRecoverySql, /floor_quantity \* product_mark\.price - calc\.floor_cost/);
assert.match(floorRecoverySql, /recovered_points \+ outstanding_points = recovery_amount/);
assert.match(floorRecoverySql, /before update of points on public\.gacha_s2_player_states/);
assert.match(floorRecoverySql, /when \(new\.points > old\.points\)/);
assert.match(floorRecoverySql, /market-100p-floor-recovery-notice-20260813/);
assert.doesNotMatch(floorRecoverySql, /nickname|display_name|account\.id \|\|/);
assert.match(floorRecoveryCorrectionSql, /create table if not exists public\.gacha_s2_market_floor_recovery_corrections/);
assert.match(floorRecoveryCorrectionSql, /v_event\.product_price = 100/);
assert.match(floorRecoveryCorrectionSql, /v_event\.underlying_price < v_state\.previous_underlying_price/);
assert.match(floorRecoveryCorrectionSql, /v_event\.underlying_price > v_state\.previous_underlying_price/);
assert.match(floorRecoveryCorrectionSql, /v_event\.underlying_price <= v_threshold/);
assert.match(floorRecoveryCorrectionSql, /v_event\.underlying_price >= v_threshold/);
assert.match(floorRecoveryCorrectionSql, /set qualified = true/);
assert.match(floorRecoveryCorrectionSql, /refund_points = greatest\(0, recovered_before_correction - revised_recovery_amount\)/);
assert.match(floorRecoveryCorrectionSql, /effective_recovered_points \+ outstanding_points = revised_recovery_amount/);
assert.match(floorRecoveryCorrectionSql, /market-100p-floor-recovery-correction-notice-20260813/);
assert.doesNotMatch(floorRecoveryCorrectionSql, /nickname|display_name|account\.id \|\|/);
assert.match(marketCompensationSql, /create table if not exists public\.gacha_s2_market_bug_compensation_20260813/);
assert.match(marketCompensationSql, /gross_reward integer not null default 500000/);
assert.match(marketCompensationSql, /offset_applied \+ net_credited = gross_reward/);
assert.match(marketCompensationSql, /outstanding_before - outstanding_after = offset_applied/);
assert.match(marketCompensationSql, /set points = state\.points \+ reward\.gross_reward/);
assert.match(marketCompensationSql, /market-bug-global-compensation-500k-20260813/);
assert.match(lowPriceRecoverySql, /v_previous_price < v_base_price \* 0\.10/);
assert.match(lowPriceRecoverySql, /v_previous_price < v_base_price \* 0\.20/);
assert.match(lowPriceRecoverySql, /v_direction_roll < 0\.75/);
assert.match(lowPriceRecoverySql, /new\.trend_direction := 1/);
assert.match(lowPriceRecoverySql, /new\.trend_remaining := floor\(1 \+ v_length_roll \* 3\)/);
assert.match(lowPriceRecoverySql, /gacha_s2_00_apply_market_low_price_recovery_trigger/);
assert.match(vitamingNextLimitDownSql, /'vtm', timestamptz '2026-08-13 23:00:00\+09', -3000/);
assert.match(vitamingNextLimitDownSql, /on conflict \(symbol, hour_at\) do update/);

assert.match(html, /data-minigame-select="market"/);
assert.match(html, /id="marketShell"/);
assert.match(html, /id="marketBuyButton"/);
assert.match(html, /aria-label="오늘 시간별 가격 차트"/);
assert.match(html, /id="marketProductSelect"/);
assert.match(html, /id="marketHoldingCount"/);
assert.match(html, /id="marketHoldingList"/);
assert.match(html, /레버리지 x5/);
assert.match(html, /인버스 x5/);
assert.match(html, /전체\/종목당 투자 원금 최대 1,000,000P/);
assert.match(css, /\.market-shell/);
assert.match(css, /\.market-holding-row/);
assert.match(controller, /loadMarketState/);
assert.match(controller, /submitMarketTrade/);
assert.match(controller, /serverCommands\?\.marketTrade/);
assert.match(controller, /marketReturnRate\(unrealized, invested\)/);
assert.match(controller, /marketHoldings\(assets\)/);
assert.match(controller, /data-market-holding/);
assert.match(controller, /marketHoldingList\?\.addEventListener\('click'/);
assert.match(controller, /marketProductRiskText/);
assert.match(controller, /buySuspended/);
assert.match(controller, /가격 보호 구간의 레버리지·인버스 상품은 신규 매수할 수 없습니다/);
assert.match(controller, /positionType: product\.positionType/);
assert.match(controller, /오늘 · 1시간봉/);
assert.match(controller, /minigameScreen\.classList\.toggle\('market-mode', market\)/);
assert.match(css, /\.minigame-screen\.market-mode\s*\{[^}]*grid-template-columns:\s*200px/);
assert.match(css, /@media \(max-width: 900px\) and \(orientation: portrait\)[\s\S]*\.market-mode \.market-asset-list\s*\{[^}]*grid-auto-flow:\s*column/);
assert.match(css, /@media \(max-width: 900px\) and \(orientation: portrait\)[\s\S]*\.market-mode \.minigame-control\s*\{[^}]*grid-row:\s*3/);
assert.match(edge, /body\.kind === 'marketState'/);

console.log('renewal market tests passed: 14 assets, 9 products, forced liquidation, 1m caps, atomic real-P ledger');
