import { simulateBattle } from './battle.js';
import { WORLD_BOSS_RULES } from './config.js';
import { getWorldBossTier, resolveWorldBossSlot } from './worldboss-schedule.js';

export { WORLD_BOSS_RULES };

export function createWorldBossProgress(now = Date.now()) {
  const resolved = resolveWorldBossSlot(now);
  const slot = resolved.live
    ? resolved.slot
    : { id: resolved.nextSlot.id, startsAt: resolved.nextSlot.startsAt, endsAt: resolved.nextSlot.startsAt + WORLD_BOSS_RULES.eventDurationSeconds * 1000 };
  return {
    eventId: slot.id,
    startedAt: slot.startsAt,
    endsAt: slot.endsAt,
    attempts: 0,
    bestDamage: 0,
    totalDamage: 0,
    claimedTier: -1,
    lastDamage: 0,
  };
}

export function normalizeWorldBossProgress(progress, now = Date.now()) {
  const base = createWorldBossProgress(now);
  if (!progress || progress.eventId !== base.eventId || Number(progress.endsAt) <= now) return base;
  const claimedTier = Number(progress.claimedTier);
  return {
    ...base,
    ...progress,
    attempts: Math.max(0, Math.min(WORLD_BOSS_RULES.maxAttempts, Math.floor(Number(progress.attempts) || 0))),
    bestDamage: Math.max(0, Math.floor(Number(progress.bestDamage) || 0)),
    totalDamage: Math.max(0, Math.floor(Number(progress.totalDamage) || 0)),
    claimedTier: Math.max(-1, Math.min(
      WORLD_BOSS_RULES.rewardTiers.length - 1,
      Number.isFinite(claimedTier) ? Math.floor(claimedTier) : -1,
    )),
    lastDamage: Math.max(0, Math.floor(Number(progress.lastDamage) || 0)),
  };
}

export function getWorldBossSnapshot(progress, now = Date.now()) {
  const normalized = normalizeWorldBossProgress(progress, now);
  const tier = getWorldBossTier(normalized.eventId);
  const resolved = resolveWorldBossSlot(now);
  const live = resolved.live && resolved.slot.id === normalized.eventId;
  const raidEndsAt = normalized.startedAt + WORLD_BOSS_RULES.raidDurationSeconds * 1000;
  const elapsedSeconds = Math.max(0, Math.min(
    WORLD_BOSS_RULES.raidDurationSeconds,
    Math.floor((now - normalized.startedAt) / 1000),
  ));
  // balance-tune: 서버 자동딜(serverDamagePerSecond) 폐지 -> 모든 슬롯 0으로 설정되어
  // 이 항은 항상 0. 처치 여부는 오직 참가자 합산딜(totalDamage)만으로 결정된다.
  const serverDamage = Math.floor(elapsedSeconds * tier.serverDamagePerSecond);
  const totalDamage = Math.min(tier.maxHp, serverDamage + normalized.totalDamage);
  const currentHp = Math.max(0, tier.maxHp - totalDamage);
  const hpRatio = currentHp / tier.maxHp;
  const raidRemainingSeconds = Math.max(0, Math.ceil((raidEndsAt - now) / 1000));
  const resultRemainingSeconds = Math.max(0, Math.ceil((normalized.endsAt - now) / 1000));
  const secondsUntilStart = Math.max(0, Math.ceil((normalized.startedAt - now) / 1000));
  const resultsOpen = live && now >= raidEndsAt && now < normalized.endsAt;
  const active = live && now < raidEndsAt && currentHp > 0;
  return {
    progress: normalized,
    live,
    active,
    defeated: live && currentHp <= 0,
    resultsOpen,
    raidEndsAt,
    canStartAttempt: active
      && normalized.attempts < WORLD_BOSS_RULES.maxAttempts
      && raidRemainingSeconds > WORLD_BOSS_RULES.battleDuration,
    currentHp,
    maxHp: tier.maxHp,
    tier,
    hpRatio,
    phase: hpRatio > 0.66 ? 1 : hpRatio > 0.33 ? 2 : 3,
    remainingSeconds: resultsOpen ? resultRemainingSeconds : raidRemainingSeconds,
    raidRemainingSeconds,
    resultRemainingSeconds,
    secondsUntilStart,
    nextSlot: resolved.nextSlot,
    participants: 427 + Math.floor(elapsedSeconds / 9),
  };
}

export function simulateWorldBossAttempt(formation, accountBonuses, attemptNumber, eventId = WORLD_BOSS_RULES.eventId) {
  const stage = {
    id: `${eventId}:attempt:${attemptNumber}`,
    boss: true,
    enemyHp: Number.MAX_SAFE_INTEGER,
    enemyAttack: 900,
    duration: WORLD_BOSS_RULES.battleDuration,
  };
  const result = simulateBattle(formation, stage, accountBonuses);
  return {
    ...result,
    totalDamage: result.damageByCard.reduce((sum, card) => sum + card.damage, 0),
  };
}

export function recordWorldBossAttempt(progress, damage, now = Date.now()) {
  const resolved = resolveWorldBossSlot(now);
  if (!progress || Number(progress.endsAt) <= now || resolved.slot?.id !== progress.eventId) {
    throw new Error('World boss slot has ended.');
  }
  const normalized = normalizeWorldBossProgress(progress, now);
  if (!getWorldBossSnapshot(normalized, now).active) throw new Error('World boss event is not active.');
  if (normalized.attempts >= WORLD_BOSS_RULES.maxAttempts) throw new Error('World boss attempt limit reached.');
  const safeDamage = Math.max(0, Math.floor(Number(damage) || 0));
  return {
    ...normalized,
    attempts: normalized.attempts + 1,
    bestDamage: Math.max(normalized.bestDamage, safeDamage),
    totalDamage: normalized.totalDamage + safeDamage,
    lastDamage: safeDamage,
  };
}

export function getWorldBossReward(progress, now = Date.now()) {
  const snapshot = getWorldBossSnapshot(progress, now);
  const normalized = snapshot.progress;
  const earnedTier = WORLD_BOSS_RULES.rewardTiers.reduce((highest, tier, index) => (
    normalized.attempts > 0 && normalized.totalDamage >= tier.damage ? index : highest
  ), -1);
  const storedClaimedTier = Number(normalized.claimedTier);
  const claimedTier = Math.max(-1, Number.isFinite(storedClaimedTier) ? Math.floor(storedClaimedTier) : -1);
  const earned = earnedTier >= 0 ? WORLD_BOSS_RULES.rewardTiers[earnedTier] : { points: 0, failurePoints: 0 };
  const points = snapshot.defeated ? earned.points : earned.failurePoints;
  return {
    earnedTier,
    claimedTier,
    points: snapshot.resultsOpen && earnedTier > claimedTier ? points : 0,
    previewPoints: points,
    successPoints: earned.points,
    failurePoints: earned.failurePoints,
    defeated: snapshot.defeated,
    resultsOpen: snapshot.resultsOpen,
    available: snapshot.resultsOpen && earnedTier > claimedTier,
  };
}

export function claimWorldBossReward(progress, now = Date.now()) {
  const normalized = normalizeWorldBossProgress(progress, now);
  const reward = getWorldBossReward(normalized, now);
  if (!reward.available) return { progress: normalized, reward };
  return { progress: { ...normalized, claimedTier: reward.earnedTier }, reward };
}
