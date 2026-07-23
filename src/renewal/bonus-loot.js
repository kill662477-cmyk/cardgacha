import { BONUS_DROP_RULES, SUPPORT_ITEMS, WORLD_BOSS_RULES } from './config.js';
import { getWorldBossTier } from './worldboss-schedule.js';
import { weightedPick } from './shop.js';

function safeRandom(random) {
  return Math.max(0, Math.min(0.999999999, Number(random()) || 0));
}

function rollDrop(rule, random) {
  if (!rule || safeRandom(random) >= rule.dropRate) return null;
  const isPack = safeRandom(random) < rule.packShare;
  const itemId = weightedPick(
    isPack ? BONUS_DROP_RULES.packWeights : BONUS_DROP_RULES.itemWeights,
    safeRandom(random),
  );
  const item = SUPPORT_ITEMS[itemId];
  if (!item) throw new Error(`Unknown bonus drop item: ${itemId}`);
  return { itemId, name: item.name, category: item.category, isPack };
}

export function adventureBonusDropRule(clearedStages) {
  const cleared = Math.max(0, Math.floor(Number(clearedStages) || 0));
  return [...BONUS_DROP_RULES.adventureTiers]
    .reverse()
    .find((tier) => cleared >= tier.minClearedStages) ?? null;
}

export function rollAdventureBonusDrop(clearedStages, random = Math.random) {
  return rollDrop(adventureBonusDropRule(clearedStages), random);
}

export function rollWorldBossBonusDrop(defeated, random = Math.random) {
  return rollDrop(BONUS_DROP_RULES.worldBoss[defeated ? 'cleared' : 'failed'], random);
}

export function rollWorldBossDestructionGuardDrop(eventId, defeated, random = Math.random) {
  const rate = Number(getWorldBossTier(eventId, WORLD_BOSS_RULES).clearDestructionGuardRate) || 0;
  if (!defeated || safeRandom(random) >= rate) return null;
  const item = SUPPORT_ITEMS.destructionGuard;
  return { itemId: 'destructionGuard', name: item.name, category: item.category, isPack: false };
}

export function grantBonusDrop(inventory, drop) {
  if (!drop) return { ...inventory };
  return { ...inventory, [drop.itemId]: (inventory?.[drop.itemId] ?? 0) + 1 };
}

export function bonusDropText(drop) {
  return drop ? `추가 획득 · ${drop.name}` : '';
}
