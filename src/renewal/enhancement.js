import { ENHANCEMENT, MATERIAL_RULES } from './config.js';
import { cardExpRequired } from './rewards.js';

export { MATERIAL_RULES };

export function getEnhancementOdds(card, booster = 'none') {
  const target = Math.min(9, (card.enhancement ?? 0) + 1);
  const baseSuccess = ENHANCEMENT.baseSuccessRates[target] ?? 0;
  const penalty = target <= 3 ? 0 : (ENHANCEMENT.rarityPenalties[card.rarity] ?? 0);
  const boosterBonus = booster === 'enhance5' ? 5 : booster === 'enhance10' ? 10 : 0;
  const success = target <= 3 ? 100 : Math.min(95, Math.max(0, baseSuccess - penalty + boosterBonus));
  const destroy = ENHANCEMENT.destroyRates[target] ?? 0;
  return { target, success, destroy, fail: Math.max(0, 100 - success - destroy) };
}

export function availableDuplicateCount(cardId, copies, locks = {}) {
  if (locks[cardId]) return 0;
  return Math.max(0, (copies[cardId] ?? 0) - 1);
}

export function selectEnhancementMaterials(targetCard, cards, copies, locks = {}, optionIndex = 0) {
  const options = MATERIAL_RULES[targetCard.rarity] ?? [];
  const rule = options[optionIndex] ?? options[0];
  if (!rule) return { rule: null, selected: [], available: 0, ready: false };

  const candidates = cards
    .filter((card) => card.rarity === rule.rarity && !locks[card.id])
    .map((card) => ({ card, available: availableDuplicateCount(card.id, copies, locks) }))
    .filter((entry) => entry.available > 0)
    .sort((left, right) => left.card.id.localeCompare(right.card.id));
  const selected = [];
  candidates.forEach(({ card, available }) => {
    const needed = rule.count - selected.length;
    for (let index = 0; index < Math.min(needed, available); index += 1) selected.push(card.id);
  });
  return {
    rule,
    selected,
    available: candidates.reduce((sum, entry) => sum + entry.available, 0),
    ready: selected.length === rule.count,
  };
}

export function getEnhancementGate(card, materialSelection, points, booster = 'none', supportItems = {}) {
  if (!card) return { ready: false, reason: '대상 카드 없음' };
  if ((card.enhancement ?? 0) >= 9) return { ready: false, reason: '최대 강화 완료' };
  const requiredExp = cardExpRequired(card.enhancement ?? 0);
  if ((card.exp ?? 0) < requiredExp) return { ready: false, reason: `경험치 부족 ${card.exp ?? 0}/${requiredExp}` };
  if (!materialSelection?.ready) return { ready: false, reason: '중복 재료 부족' };
  const target = (card.enhancement ?? 0) + 1;
  if (target === 9 && points < ENHANCEMENT.plusNinePointCost) return { ready: false, reason: `포인트 ${ENHANCEMENT.plusNinePointCost}P 필요` };
  if (booster !== 'none' && (supportItems[booster] ?? 0) <= 0) return { ready: false, reason: '선택 보조제 없음' };
  if ((booster === 'enhance5' || booster === 'enhance10') && target < 4) return { ready: false, reason: '촉진제는 +4부터 사용 가능' };
  if (booster === 'destructionGuard' && target < 7) return { ready: false, reason: '파괴 차단제는 +7부터 사용 가능' };
  return { ready: true, reason: '강화 가능' };
}

export function resolveEnhancement(card, booster = 'none', randomValue = Math.random()) {
  const odds = getEnhancementOdds(card, booster);
  const roll = Math.max(0, Math.min(0.999999, randomValue)) * 100;
  if (roll < odds.success) return { outcome: 'success', blocked: false, odds, roll };
  if (roll < odds.success + odds.destroy) {
    if (booster === 'destructionGuard') return { outcome: 'fail', blocked: true, odds, roll };
    return { outcome: 'destroy', blocked: false, odds, roll };
  }
  return { outcome: 'fail', blocked: false, odds, roll };
}

export function applyEnhancementResult(card, result) {
  if (result?.outcome === 'success') return { enhancement: result.odds.target, exp: 0 };
  if (result?.outcome === 'destroy') return { enhancement: 0, exp: 0 };
  return { enhancement: card.enhancement ?? 0, exp: card.exp ?? 0 };
}

export function consumeSelectedMaterials(copies, selected) {
  const next = { ...copies };
  selected.forEach((cardId) => { next[cardId] = Math.max(0, (next[cardId] ?? 0) - 1); });
  return next;
}
