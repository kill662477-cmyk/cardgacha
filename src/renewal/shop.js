import { PACKS, SUPPORT_ITEMS, SUPPORT_PACK } from './config.js';
import { normalizeAdventureRuns } from './adventure.js';
import { normalizeQuickBattle } from './rewards.js';

export function weightedPick(weights, randomValue = Math.random()) {
  const entries = Object.entries(weights).filter(([, weight]) => Number(weight) > 0);
  const total = entries.reduce((sum, [, weight]) => sum + Number(weight), 0);
  if (total <= 0) return null;
  let roll = Math.max(0, Math.min(0.999999999, randomValue)) * total;
  for (const [key, weight] of entries) {
    roll -= Number(weight);
    if (roll < 0) return key;
  }
  return entries.at(-1)?.[0] ?? null;
}

export function cardResultGridLayout(count) {
  const safeCount = Math.max(1, Number(count) || 1);
  if (safeCount <= 4) return { columns: safeCount, cardWidth: '150px', bulk: false };
  if (safeCount <= 10) return { columns: 5, cardWidth: '125px', bulk: false };
  return { columns: Math.min(8, safeCount), cardWidth: '1fr', bulk: true };
}

export function effectivePackRates(packKey, cards, race = null) {
  const pack = PACKS[packKey];
  if (!pack) throw new Error(`Unknown card pack: ${packKey}`);
  const available = Object.fromEntries(Object.entries(pack.rates).filter(([rarity]) => cards.some((card) => (
    card.rarity === rarity && (!race || card.race === race)
  ))));
  const total = Object.values(available).reduce((sum, rate) => sum + rate, 0);
  if (total <= 0) return {};
  return Object.fromEntries(Object.entries(available).map(([rarity, rate]) => [rarity, rate / total * 100]));
}

export function drawCardPack(packKey, cards, options = {}) {
  const pack = PACKS[packKey];
  if (!pack) throw new Error(`Unknown card pack: ${packKey}`);
  const race = packKey === 'race' ? options.race : null;
  if (packKey === 'race' && !race) throw new Error('Race pack requires a race.');
  const random = options.random ?? Math.random;
  const rates = effectivePackRates(packKey, cards, race);
  return Array.from({ length: pack.count }, () => {
    const rarity = weightedPick(rates, random());
    const candidates = cards.filter((card) => card.rarity === rarity && (!race || card.race === race));
    if (candidates.length === 0) throw new Error(`No ${race ?? 'all'} ${rarity} cards available.`);
    return candidates[Math.min(candidates.length - 1, Math.floor(random() * candidates.length))].id;
  });
}

export function drawSupportPack(count = 1, random = Math.random) {
  if (count !== 1 && count !== 10) throw new Error('Support pack count must be 1 or 10.');
  const results = [];
  const normalSlots = count === 10 ? 9 : count;
  for (let index = 0; index < normalSlots; index += 1) results.push(weightedPick(SUPPORT_PACK.items, random()));
  if (count === 10) {
    const hasRare = results.some((itemId) => SUPPORT_PACK.rareItems.includes(itemId));
    results.push(weightedPick(hasRare ? SUPPORT_PACK.items : SUPPORT_PACK.guaranteeRates, random()));
  }
  return results;
}

export function addCardResults(copies, collectionRecords, cardIds) {
  const nextCopies = { ...copies };
  const nextRecords = { ...collectionRecords };
  cardIds.forEach((cardId) => {
    nextCopies[cardId] = (nextCopies[cardId] ?? 0) + 1;
    nextRecords[cardId] = true;
  });
  return { copies: nextCopies, collectionRecords: nextRecords };
}

export function addSupportResults(inventory, itemIds) {
  const next = { ...inventory };
  itemIds.forEach((itemId) => { next[itemId] = (next[itemId] ?? 0) + 1; });
  return next;
}

export function useSupportItem(state, itemId, now = Date.now()) {
  const item = SUPPORT_ITEMS[itemId];
  if (!item || (state.supportItems[itemId] ?? 0) <= 0) return { used: false, reason: '보유 아이템 없음', state };
  const next = {
    ...state,
    supportItems: { ...state.supportItems, [itemId]: state.supportItems[itemId] - 1 },
    activeBuffs: { ...state.activeBuffs },
  };
  if (item.energy) {
    const cap = state.maxActionEnergy * 2;
    if (state.actionEnergy >= cap) return { used: false, reason: `행동력 초과 충전 한도 ${cap}`, state };
    next.actionEnergy = Math.min(cap, state.actionEnergy + item.energy);
    next.lastEnergyAt = now;
  } else if (item.durationMinutes) {
    const currentEnd = Math.max(now, Number(state.activeBuffs?.cardExpEndAt) || 0);
    next.activeBuffs.cardExpStartAt = currentEnd > now ? state.activeBuffs.cardExpStartAt : now;
    next.activeBuffs.cardExpEndAt = currentEnd + item.durationMinutes * 60 * 1000;
  } else if (item.reset === 'adventureRuns') {
    const runs = normalizeAdventureRuns(state.adventureRuns, now);
    if (runs.count <= 0) return { used: false, reason: '초기화할 모험 시작 횟수 없음', state };
    next.adventureRuns = { windowStartedAt: 0, count: 0 };
  } else if (item.reset === 'quickBattle') {
    const quickBattle = normalizeQuickBattle(state.quickBattle, now);
    if (quickBattle.count <= 0) return { used: false, reason: '초기화할 빠른 전투 횟수 없음', state };
    next.quickBattle = { ...quickBattle, count: 0 };
  } else {
    return { used: false, reason: '이 화면에서 직접 사용할 수 없는 아이템', state };
  }
  return { used: true, reason: `${item.name} 사용`, state: next };
}

export function useCardExpPotion(state, cardId, requiredExp) {
  const item = SUPPORT_ITEMS.cardExpPotion;
  const current = state.cardProgress[cardId] ?? { enhancement: 0, exp: 0 };
  const required = Math.max(0, Number(requiredExp) || 0);
  if ((state.supportItems.cardExpPotion ?? 0) <= 0) return { used: false, reason: '카드 EXP 포션 없음', state };
  if (required <= 0 || current.exp >= required) return { used: false, reason: '현재 강화 경험치 MAX', state };
  const gained = Math.min(item.cardExp, required - current.exp);
  return {
    used: true,
    gained,
    reason: `카드 EXP +${gained}`,
    state: {
      ...state,
      supportItems: { ...state.supportItems, cardExpPotion: state.supportItems.cardExpPotion - 1 },
      cardProgress: {
        ...state.cardProgress,
        [cardId]: { ...current, exp: current.exp + gained },
      },
    },
  };
}

export function cardExpBoostSeconds(activeBuffs, from, to) {
  const start = Math.max(from, Number(activeBuffs?.cardExpStartAt) || 0);
  const end = Math.min(to, Number(activeBuffs?.cardExpEndAt) || 0);
  return Math.max(0, Math.floor((end - start) / 1000));
}
