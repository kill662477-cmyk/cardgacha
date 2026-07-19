import { ADVENTURE_RULES, ENHANCEMENT, REWARD_RULES } from './config.js';

export function localDateKey(timestamp = Date.now()) {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

export function cardExpRequired(enhancement) {
  return ENHANCEMENT.expRequirements[enhancement] ?? 0;
}

export function rewardRates(stageNumber) {
  const stage = Math.max(1, Math.min(REWARD_RULES.maxStage, Number(stageNumber) || 1));
  return {
    // nolevel-1: 계정 EXP 제거. 카드 EXP만 보상으로 지급한다.
    cardExpPerMinute: REWARD_RULES.cardExpBasePerMinute + stage * REWARD_RULES.cardExpPerStage,
  };
}

export function calculateIdleReward(elapsedMs, stageNumber, options = {}) {
  const capHours = options.capHours ?? REWARD_RULES.offlineCapHours;
  const cappedMs = Math.min(Math.max(0, elapsedMs), capHours * 60 * 60 * 1000);
  const elapsedSeconds = Math.floor(cappedMs / 1000);
  const elapsedMinutes = elapsedSeconds / 60;
  const rates = rewardRates(stageNumber);
  const idleMultiplier = 1 + Math.max(0, Number(options.idleBonus) || 0);
  const boostedSeconds = Math.min(elapsedSeconds, Math.max(0, Number(options.cardExpBoostSeconds) || 0));
  const baseCardExp = Math.floor(rates.cardExpPerMinute * elapsedMinutes * idleMultiplier);
  const boostedCardExp = boostedSeconds > 0
    ? Math.max(1, Math.floor(rates.cardExpPerMinute * boostedSeconds / 60 * 0.5 * idleMultiplier))
    : 0;
  return {
    elapsedSeconds,
    cardExp: baseCardExp + boostedCardExp,
    rates,
  };
}

export function applyCardExperience(cardProgress, formation, gainedExp) {
  const nextProgress = { ...cardProgress };
  formation.forEach((card) => {
    const current = nextProgress[card.id] ?? { enhancement: card.enhancement ?? 0, exp: card.exp ?? 0 };
    const required = cardExpRequired(current.enhancement);
    nextProgress[card.id] = {
      ...current,
      exp: required === 0 ? 0 : Math.min(required, Math.max(0, current.exp) + Math.max(0, gainedExp)),
    };
  });
  return nextProgress;
}

export function recoverEnergy(state, now = Date.now()) {
  const intervalMs = REWARD_RULES.energyRecoveryMinutes * 60 * 1000;
  const lastEnergyAt = Number(state.lastEnergyAt) || now;
  if (state.actionEnergy >= state.maxActionEnergy) {
    return { energy: state.maxActionEnergy, lastEnergyAt, recovered: 0 };
  }
  const recovered = Math.floor(Math.max(0, now - lastEnergyAt) / intervalMs);
  if (recovered <= 0) return { energy: state.actionEnergy, lastEnergyAt, recovered: 0 };
  const energy = Math.min(state.maxActionEnergy, state.actionEnergy + recovered);
  return {
    energy,
    lastEnergyAt: energy >= state.maxActionEnergy ? now : lastEnergyAt + recovered * intervalMs,
    recovered: energy - state.actionEnergy,
  };
}

// 빠른 전투 횟수는 달력 날짜가 아니라 모험 런과 동일한 4시간 롤링 윈도우로 초기화된다.
// (모험 런의 4시간 풀과는 별개로 자체 windowStartedAt/count를 갖는다.)
export function normalizeQuickBattle(quickBattle, now = Date.now()) {
  const startedAt = Math.max(0, Number(quickBattle?.windowStartedAt) || 0);
  const count = Math.max(0, Math.floor(Number(quickBattle?.count) || 0));
  if (startedAt === 0 || now - startedAt >= ADVENTURE_RULES.runWindowMs || now < startedAt) {
    return { windowStartedAt: 0, count: 0 };
  }
  return { windowStartedAt: startedAt, count: Math.min(REWARD_RULES.quickBattleDailyLimit, count) };
}

export function getQuickBattleLimitStatus(quickBattle, now = Date.now()) {
  const normalized = normalizeQuickBattle(quickBattle, now);
  return {
    progress: normalized,
    remaining: REWARD_RULES.quickBattleDailyLimit - normalized.count,
    resetsInMs: normalized.windowStartedAt === 0
      ? 0
      : Math.max(0, normalized.windowStartedAt + ADVENTURE_RULES.runWindowMs - now),
  };
}

export function recordQuickBattle(quickBattle, now = Date.now()) {
  const status = getQuickBattleLimitStatus(quickBattle, now);
  if (status.remaining <= 0) throw new Error('Quick battle limit reached.');
  return {
    windowStartedAt: status.progress.windowStartedAt || now,
    count: status.progress.count + 1,
  };
}
