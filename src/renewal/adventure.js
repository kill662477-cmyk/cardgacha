import { ADVENTURE_RULES, EX_DISTRIBUTION_RULES } from './config.js';

export function normalizeAdventureMode(mode) {
  return mode === 'hard' ? 'hard' : 'normal';
}

export function adventureModeRules(mode) {
  return ADVENTURE_RULES.modes[normalizeAdventureMode(mode)];
}

export function isAdventureModeUnlocked(mode, highestClearedStage = 0) {
  return Number(highestClearedStage) >= adventureModeRules(mode).unlockStage;
}

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
  const mode = normalizeAdventureMode(run.mode);
  const rules = adventureModeRules(mode);
  const clearedStages = Math.max(0, Math.min(
    rules.stageCount,
    Math.floor(Number(run.clearedStages) || 0),
  ));
  const normalized = {
    active: true,
    mode,
    currentStage: Math.max(
      rules.startStage,
      Math.min(rules.endStage, Math.floor(Number(run.currentStage) || rules.startStage)),
    ),
    clearedStages,
    startedAt: Math.max(0, Number(run.startedAt) || 0),
  };
  if (typeof run.runId === 'string' && run.runId.trim()) normalized.runId = run.runId;
  if (Number.isInteger(run.verifiedClearedStages)
    && run.verifiedClearedStages >= 0
    && run.verifiedClearedStages <= rules.stageCount) {
    normalized.verifiedClearedStages = run.verifiedClearedStages;
  }
  if (typeof run.verificationDigest === 'string' && /^[0-9a-f]{64}$/i.test(run.verificationDigest)) {
    normalized.verificationDigest = run.verificationDigest.toLowerCase();
  }
  return normalized;
}

export function createAdventureRun(now = Date.now(), mode = 'normal') {
  const normalizedMode = normalizeAdventureMode(mode);
  return {
    active: true,
    mode: normalizedMode,
    currentStage: adventureModeRules(normalizedMode).startStage,
    clearedStages: 0,
    startedAt: now,
  };
}

export function advanceAdventureRun(run) {
  const normalized = normalizeAdventureRun(run);
  if (!normalized.active) throw new Error('Adventure run is not active.');
  const rules = adventureModeRules(normalized.mode);
  return {
    ...normalized,
    currentStage: Math.min(rules.endStage, normalized.currentStage + 1),
    clearedStages: Math.min(rules.stageCount, normalized.clearedStages + 1),
  };
}

export function calculateAdventureRunReward(clearedStages, mode = 'normal') {
  const cleared = Math.max(0, Math.floor(Number(clearedStages) || 0));
  if (normalizeAdventureMode(mode) === 'hard') {
    const rules = ADVENTURE_RULES.hardRunReward;
    const stageCount = ADVENTURE_RULES.modes.hard.stageCount;
    const points = cleared <= 0
      ? 0
      : Math.floor(rules.minPointsPerRun
        + (rules.maxPointsPerRun - rules.minPointsPerRun) * (Math.min(cleared, stageCount) - 1) / (stageCount - 1));
    return {
      clearedStages: Math.min(cleared, stageCount),
      points,
      cardExp: Math.min(cleared, stageCount) * rules.cardExpPerClearedStage,
    };
  }
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
