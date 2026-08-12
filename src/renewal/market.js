export const MARKET_RULES = Object.freeze({
  label: '캄스증권',
  feeRate: 0.015,
  totalInvestmentCap: 1_000_000,
  perAssetInvestmentCap: 1_000_000,
  hourlyChangeCap: 0.30,
  productPriceFloor: 100,
  productPriceCapMultiplier: 10,
  historyResetsDaily: true,
  historyTimeZone: 'Asia/Seoul',
});

export const MARKET_PRODUCTS = Object.freeze([
  { key: 'long:1', positionType: 'long', multiplier: 1, label: '일반' },
  ...[2, 3, 4, 5].map((multiplier) => ({
    key: 'long:' + multiplier,
    positionType: 'long',
    multiplier,
    label: '레버리지 x' + multiplier,
  })),
  ...[2, 3, 4, 5].map((multiplier) => ({
    key: 'inverse:' + multiplier,
    positionType: 'inverse',
    multiplier,
    label: '인버스 x' + multiplier,
  })),
]);

export const MARKET_ASSETS = Object.freeze([
  { symbol: 'KYH', name: '김윤환', cardId: 'kimyunhwan-4', basePrice: 12_000 },
  { symbol: 'NDS', name: '남덕선', cardId: 'namdeokseon-12', basePrice: 9_400 },
  { symbol: 'TMT', name: '토마토', cardId: 'tomato-11', basePrice: 15_000 },
  { symbol: 'JDD', name: '지두두', cardId: 'jidudu-14', basePrice: 13_500 },
  { symbol: 'SUN', name: '햇살', cardId: 'haetsal-12', basePrice: 10_800 },
  { symbol: 'JJK', name: '찌킹', cardId: 'jjiking-12', basePrice: 8_800 },
  { symbol: 'CHR', name: '치리', cardId: 'chiri-19', basePrice: 7_600 },
  { symbol: 'SJY', name: '소주양', cardId: 'sojuyang-13', basePrice: 11_200 },
  { symbol: 'JHR', name: '주하랑', cardId: 'juharang-18', basePrice: 16_500 },
  { symbol: 'JOY', name: '임조이', cardId: 'imjoy-12', basePrice: 9_900 },
  { symbol: 'VTM', name: '비타밍', cardId: 'vitaming-14', basePrice: 12_800 },
  { symbol: 'MJG', name: '먼진', cardId: 'meonjin-12', basePrice: 8_200 },
  { symbol: 'ARS', name: '아리송이', cardId: 'arisongi-11', basePrice: 14_200 },
  { symbol: 'NGN', name: '낭니', cardId: 'nangni-8', basePrice: 17_000 },
]);

export function normalizeMarketQuantity(value) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : 0;
}

export function marketFee(grossPoints, feeRate = MARKET_RULES.feeRate) {
  return Math.max(1, Math.ceil(Math.max(0, Number(grossPoints) || 0) * feeRate));
}

export function marketReturnRate(unrealizedPnl, investedPoints) {
  const invested = Number(investedPoints);
  if (!Number.isFinite(invested) || invested <= 0) return 0;
  const rate = (Number(unrealizedPnl) || 0) / invested * 100;
  return Number.isFinite(rate) ? rate : 0;
}

export function normalizeMarketProduct(positionType = 'long', multiplier = 1) {
  const type = positionType === 'inverse' ? 'inverse' : 'long';
  const multiple = Number(multiplier);
  return MARKET_PRODUCTS.find((product) => (
    product.positionType === type && product.multiplier === multiple
  )) ?? MARKET_PRODUCTS[0];
}

export function marketProductLabel(positionType = 'long', multiplier = 1) {
  return normalizeMarketProduct(positionType, multiplier).label;
}

export function marketProductChangeRate(underlyingChangeRate, positionType = 'long', multiplier = 1) {
  const product = normalizeMarketProduct(positionType, multiplier);
  const direction = product.positionType === 'inverse' ? -1 : 1;
  return (Number(underlyingChangeRate) || 0) * direction * product.multiplier;
}

export function nextMarketProductPrice(previousPrice, underlyingChangeRate, {
  positionType = 'long',
  multiplier = 1,
  basePrice = previousPrice,
} = {}) {
  const previous = Math.max(MARKET_RULES.productPriceFloor, Math.round(Number(previousPrice) || 1));
  const cap = Math.max(MARKET_RULES.productPriceFloor, Math.round(Number(basePrice) || 1) * MARKET_RULES.productPriceCapMultiplier);
  return Math.max(
    MARKET_RULES.productPriceFloor,
    Math.min(cap, Math.round(previous * (1 + marketProductChangeRate(underlyingChangeRate, positionType, multiplier)))),
  );
}

export function nextMarketPrice(previousPrice, changeRate) {
  const previous = Math.max(1, Math.round(Number(previousPrice) || 1));
  const bounded = Math.max(-MARKET_RULES.hourlyChangeCap, Math.min(MARKET_RULES.hourlyChangeCap, Number(changeRate) || 0));
  return Math.max(100, Math.round(previous * (1 + bounded)));
}

export function canAddMarketInvestment({ totalCostBasis = 0, assetCostBasis = 0, purchaseCost = 0 } = {}) {
  const added = Math.max(0, Math.round(Number(purchaseCost) || 0));
  return Number(totalCostBasis) + added <= MARKET_RULES.totalInvestmentCap
    && Number(assetCostBasis) + added <= MARKET_RULES.perAssetInvestmentCap;
}
