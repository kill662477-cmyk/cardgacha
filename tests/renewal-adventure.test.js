import assert from 'node:assert/strict';
import { ADVENTURE_RULES } from '../src/renewal/config.js';
import {
  advanceAdventureRun,
  calculateAdventureRunReward,
  claimAdventureExMilestones,
  createAdventureRun,
  getAdventureRunLimitStatus,
  normalizeAdventureRun,
  normalizeAdventureRuns,
  recordAdventureRun,
  isAdventureModeUnlocked,
} from '../src/renewal/adventure.js';

const now = Date.UTC(2026, 6, 17, 12, 0, 0);
assert.equal(ADVENTURE_RULES.runWindowMs, 4 * 60 * 60 * 1000, 'adventure run window must last 4 hours');
let progress = normalizeAdventureRuns(null, now);
assert.equal(getAdventureRunLimitStatus(progress, now).remaining, 3);
progress = recordAdventureRun(progress, now + 1);
assert.equal(progress.windowStartedAt, now + 1, 'the rolling 4-hour window must start on the first run');
progress = recordAdventureRun(progress, now + 2);
progress = recordAdventureRun(progress, now + 3);
assert.equal(getAdventureRunLimitStatus(progress, now + 4).remaining, 0);
assert.throws(() => recordAdventureRun(progress, now + 5), /run limit/);
assert.equal(
  getAdventureRunLimitStatus(progress, now + 1 + 3 * 60 * 60 * 1000).remaining,
  0,
  'the run limit must remain active before 4 hours elapse',
);

const resetAt = now + 1 + ADVENTURE_RULES.runWindowMs;
const reset = normalizeAdventureRuns(progress, resetAt);
assert.equal(reset.count, 0);
assert.equal(getAdventureRunLimitStatus(reset, resetAt).remaining, 3);

let run = createAdventureRun(now);
assert.equal(run.currentStage, 1, 'every run must begin at stage 1');
run = advanceAdventureRun(run);
run = advanceAdventureRun(run);
assert.equal(run.currentStage, 3);
assert.equal(run.clearedStages, 2);
assert.equal(normalizeAdventureRun(null).currentStage, 1);
const resumedRun = normalizeAdventureRun({
  active: true,
  currentStage: 3,
  clearedStages: 2,
  startedAt: now,
  runId: 'server-run-1',
  verifiedClearedStages: 7,
  verificationDigest: 'A'.repeat(64),
});
assert.equal(resumedRun.runId, 'server-run-1');
assert.equal(resumedRun.verifiedClearedStages, 7);
assert.equal(resumedRun.verificationDigest, 'a'.repeat(64));
assert.deepEqual(calculateAdventureRunReward(3), {
  clearedStages: 3,
  points: 93,
  cardExp: 3,
});
assert.equal(calculateAdventureRunReward(10).points, 502);
assert.equal(calculateAdventureRunReward(50).points, 8000);
assert.equal(calculateAdventureRunReward(99).points, 8000, 'run point reward must cap at 8,000P');
const hardRun = createAdventureRun(now, 'hard');
assert.equal(hardRun.currentStage, 51);
assert.equal(hardRun.mode, 'hard');
assert.equal(advanceAdventureRun(hardRun).currentStage, 52);
assert.equal(calculateAdventureRunReward(0, 'hard').points, 0);
assert.equal(calculateAdventureRunReward(1, 'hard').points, 7000);
assert.equal(calculateAdventureRunReward(50, 'hard').points, 20000);
assert.equal(isAdventureModeUnlocked('hard', 49), false);
assert.equal(isAdventureModeUnlocked('hard', 50), true);

const exGrant = claimAdventureExMilestones(20, {}, {}, {});
assert.deepEqual(exGrant.awarded.map((reward) => reward.cardId), ['group-1', 'group-2', 'group-3', 'group-4']);
assert.equal(exGrant.copies['group-4'], 1);
assert.equal(exGrant.records['group-4'], true);
assert.equal(claimAdventureExMilestones(20, exGrant.claims, exGrant.copies, exGrant.records).awarded.length, 0);

console.log('renewal adventure tests passed: 3 runs per rolling 4 hours, stage-1 entry, rewards by cleared stages');
