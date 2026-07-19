import { ADVENTURE_RULES, EX_DISTRIBUTION_RULES } from './config.js';

export function normalizeAdventureRuns(progress, now = Date.now()) {
  const startedAt = Math.max(0, Number(progress?.windowStartedAt) || 0);
  const count = Math.max(0, Math.floor(Number(progress?.count) || 0));
  if (startedAt === 0 || now - startedAt >= ADVENTURE_RULES.runWindowMs || now < startedAt) {
    return { windowStartedAt: 0, count: 0 };
  }
  return { windowStartedAt: startedAt, count: Math.min(ADVENTURE_RULES.maxRunsPerWindow, count) };
}

export function getAdventureRunLimitStatus(progress, now = Date.now()) {
  const normalized = normalizeAdventureRuns(progress, now);
  return {
    progress: normalized,
    remaining: ADVENTURE_RULES.maxRunsPerWindow - normalized.count,
    resetsInMs: normalized.windowStartedAt === 0
      ? 0
      : Math.max(0, normalized.windowStartedAt + ADVENTURE_RULES.runWindowMs - now),
  };
}

export function recordAdventureRun(progress, now = Date.now()) {
  const status = getAdventureRunLimitStatus(progress, now);
  if (status.remaining <= 0) throw new Error('Adventure run limit reached.');
  return {
    windowStartedAt: status.progress.windowStartedAt || now,
    count: status.progress.count + 1,
  };
}

export function normalizeAdventureRun(run) {
  if (!run?.active) return { active: false, currentStage: 1, clearedStages: 0, startedAt: 0 };
  const normalized = {
    active: true,
    currentStage: Math.max(1, Math.floor(Number(run.currentStage) || 1)),
    clearedStages: Math.max(0, Math.floor(Number(run.clearedStages) || 0)),
    startedAt: Math.max(0, Number(run.startedAt) || 0),
  };
  if (typeof run.runId === 'string' && run.runId.trim()) normalized.runId = run.runId;
  if (Number.isInteger(run.verifiedClearedStages)
    && run.verifiedClearedStages >= 0
    && run.verifiedClearedStages <= 50) {
    normalized.verifiedClearedStages = run.verifiedClearedStages;
  }
  if (typeof run.verificationDigest === 'string' && /^[0-9a-f]{64}$/i.test(run.verificationDigest)) {
    normalized.verificationDigest = run.verificationDigest.toLowerCase();
  }
  return normalized;
}

export function createAdventureRun(now = Date.now()) {
  return { active: true, currentStage: 1, clearedStages: 0, startedAt: now };
}

export function advanceAdventureRun(run) {
  const normalized = normalizeAdventureRun(run);
  if (!normalized.active) throw new Error('Adventure run is not active.');
  return {
    ...normalized,
    currentStage: normalized.currentStage + 1,
    clearedStages: normalized.clearedStages + 1,
  };
}

export function calculateAdventureRunReward(clearedStages) {
  const cleared = Math.max(0, Math.floor(Number(clearedStages) || 0));
  const rules = ADVENTURE_RULES.runReward;
  const points = Math.floor(cleared * rules.pointsBasePerStage
    + rules.pointsGrowthPerStage * cleared * (cleared + 1) / 2);
  return {
    clearedStages: cleared,
    points: Math.min(rules.maxPointsPerRun, points),
    // nolevel-1: 계정 EXP 보상 제거. 카드 EXP만 지급한다.
    cardExp: cleared * rules.cardExpPerClearedStage,
  };
}

export function claimAdventureExMilestones(highestClearedStage, claims = {}, copies = {}, records = {}) {
  const nextClaims = { ...claims };
  const nextCopies = { ...copies };
  const nextRecords = { ...records };
  const awarded = [];
  if (EX_DISTRIBUTION_RULES.enabled) {
    EX_DISTRIBUTION_RULES.milestones.forEach(({ clearedStage, cardId }) => {
      const claimKey = String(clearedStage);
      if (highestClearedStage < clearedStage || nextClaims[claimKey]) return;
      nextClaims[claimKey] = cardId;
      nextCopies[cardId] = (nextCopies[cardId] ?? 0) + 1;
      nextRecords[cardId] = true;
      awarded.push({ clearedStage, cardId });
    });
  }
  return { claims: nextClaims, copies: nextCopies, records: nextRecords, awarded };
}
