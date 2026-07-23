import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {
  WORLD_BOSS_RULES,
  claimWorldBossReward,
  createWorldBossProgress,
  getWorldBossReward,
  getWorldBossSnapshot,
  normalizeWorldBossProgress,
  recordWorldBossAttempt,
  simulateWorldBossAttempt,
} from '../src/renewal/worldboss.js';
import { getWorldBossTier, kstSlotLabel, resolveWorldBossSlot } from '../src/renewal/worldboss-schedule.js';

const cards = JSON.parse(await fs.readFile(new URL('../data/renewal-demo-cards.json', import.meta.url), 'utf8'));
const worldBossCss = await fs.readFile(new URL('../styles/renewal/main.css', import.meta.url), 'utf8');
const formation = cards.slice(0, 5);
// KST 17:05 = UTC 08:05 -> early inside the 17:00 slot (phase 1).
const now = Date.UTC(2026, 6, 17, 8, 5, 0);
const progress = createWorldBossProgress(now);
const bonuses = { attack: 0.5, hp: 0.5, defense: 0.5, bossDamage: 0.5 };

assert.equal(progress.eventId, 'noise-zero-20260717-17', 'live progress must use the resolved slot id');

const first = simulateWorldBossAttempt(formation, bonuses, 1);
const repeat = simulateWorldBossAttempt(formation, bonuses, 1);
const second = simulateWorldBossAttempt(formation, bonuses, 2);
assert.deepEqual(first, repeat, 'same event and attempt must be deterministic');
assert.notEqual(first.seed, second.seed, 'attempt number must change battle seed');
assert.equal(first.duration, WORLD_BOSS_RULES.battleDuration);
assert.ok(first.totalDamage > 0);

let recorded = recordWorldBossAttempt(progress, first.totalDamage, now);
recorded = recordWorldBossAttempt(recorded, second.totalDamage, now);
recorded = recordWorldBossAttempt(recorded, first.totalDamage, now);
assert.equal(recorded.attempts, 3);
assert.throws(() => recordWorldBossAttempt(recorded, 1, now), /attempt limit/);
assert.equal(getWorldBossSnapshot(recorded, now).phase, 1);

const resultAt = Date.UTC(2026, 6, 17, 8, 30, 0);
const rewardBefore = getWorldBossReward(recorded, now);
assert.equal(rewardBefore.available, false, 'reward stays locked during the 30-minute raid');
const resultSnapshot = getWorldBossSnapshot(recorded, resultAt);
assert.equal(resultSnapshot.resultsOpen, true);
assert.equal(resultSnapshot.defeated, true, '20M+ personal damage clears the modeled raid gap');
const claimed = claimWorldBossReward(recorded, resultAt);
assert.equal(claimed.reward.points, 10000);
assert.equal(getWorldBossReward(claimed.progress, resultAt).available, false);

const participationOnly = claimWorldBossReward(recordWorldBossAttempt(progress, 1, now), resultAt);
assert.equal(participationOnly.progress.claimedTier, 0);
assert.equal(participationOnly.reward.defeated, false);
assert.equal(participationOnly.reward.points, 250, 'failed participation uses the reduced reward table');
assert.equal(getWorldBossReward(normalizeWorldBossProgress(participationOnly.progress, resultAt), resultAt).available, false, 'claimed participation reward must survive normalization');

// --- Schedule (KST daily slots at 17/18/19/20) ---
const kst = (y, mo, d, h, mi = 0, s = 0) => Date.UTC(y, mo - 1, d, h - 9, mi, s);

// 16:59:59 -> standby, next slot is today 17:00
const beforeFirst = resolveWorldBossSlot(kst(2026, 7, 17, 16, 59, 59));
assert.equal(beforeFirst.live, false);
assert.equal(beforeFirst.nextSlot.id, 'noise-zero-20260717-17');
assert.equal(getWorldBossSnapshot(createWorldBossProgress(kst(2026, 7, 17, 16, 59, 59)), kst(2026, 7, 17, 16, 59, 59)).active, false, 'placeholder before start is not active');

// 17:00:00 -> live, slot noise-zero-20260717-17
const atOpen = resolveWorldBossSlot(kst(2026, 7, 17, 17, 0, 0));
assert.equal(atOpen.live, true);
assert.equal(atOpen.slot.id, 'noise-zero-20260717-17');
assert.equal(getWorldBossSnapshot(createWorldBossProgress(kst(2026, 7, 17, 17, 0, 0)), kst(2026, 7, 17, 17, 0, 0)).active, true);
assert.equal(getWorldBossTier(atOpen.slot.id).maxHp, 5_000_000_000, '17:00 stays at the original baseline');
assert.equal(getWorldBossTier('noise-zero-20260717-18').maxHp, 7_500_000_000);
assert.equal(getWorldBossTier('noise-zero-20260717-19').maxHp, 11_250_000_000);
assert.equal(getWorldBossTier('noise-zero-20260717-20').maxHp, 16_875_000_000);
assert.deepEqual(
  WORLD_BOSS_RULES.scheduleHours.map((hour) => getWorldBossTier(`noise-zero-20260717-${hour}`).clearDestructionGuardRate),
  [0.05, 0.10, 0.15, 0.20],
  'clear-only destruction guard chances scale with each slot difficulty',
);

// 17:29:00 -> raid live but <=60s remain -> canStartAttempt false
const lateSnapshot = getWorldBossSnapshot(createWorldBossProgress(kst(2026, 7, 17, 17, 29, 0)), kst(2026, 7, 17, 17, 29, 0));
assert.equal(lateSnapshot.active, true);
assert.equal(lateSnapshot.canStartAttempt, false, 'attempts blocked when <= battleDuration remains');

// 17:30:00 -> combat closes and the 30-minute result/reward window opens
const resultWindow = getWorldBossSnapshot(recorded, kst(2026, 7, 17, 17, 30, 0));
assert.equal(resultWindow.active, false);
assert.equal(resultWindow.resultsOpen, true);
assert.equal(kstSlotLabel(resultWindow.raidEndsAt), '17:30');
assert.equal(getWorldBossReward(recorded, kst(2026, 7, 17, 17, 30, 0)).available, true);
const successBoundary = { ...progress, attempts: 1, totalDamage: 20_000_000 };
const belowSuccessBoundary = { ...progress, attempts: 1, totalDamage: 19_999_399 };
assert.equal(getWorldBossSnapshot(successBoundary, resultAt).defeated, true, '20M damage reaches raid clear');
assert.equal(getWorldBossSnapshot(belowSuccessBoundary, resultAt).defeated, false, 'damage below the modeled gap remains failed');

// 17:59:59 result window -> 18:00:00 next raid: slot id flips, progress resets
const endOf17 = kst(2026, 7, 17, 17, 59, 59);
const startOf18 = kst(2026, 7, 17, 18, 0, 0);
assert.equal(resolveWorldBossSlot(endOf17).slot.id, 'noise-zero-20260717-17');
assert.equal(getWorldBossSnapshot(recorded, endOf17).resultsOpen, true);
assert.equal(resolveWorldBossSlot(startOf18).slot.id, 'noise-zero-20260717-18');
const slot17Progress = { ...createWorldBossProgress(endOf17), attempts: 2, totalDamage: 5_000_000 };
const rolledOver = normalizeWorldBossProgress(slot17Progress, startOf18);
assert.equal(rolledOver.eventId, 'noise-zero-20260717-18', 'progress rolls to the new slot');
assert.equal(rolledOver.attempts, 0, 'attempts reset across slots');

// 20:59:59 -> live (last slot)
assert.equal(resolveWorldBossSlot(kst(2026, 7, 17, 20, 59, 59)).slot.id, 'noise-zero-20260717-20');

// 21:00:00 -> standby, next = tomorrow 17:00
const afterLast = resolveWorldBossSlot(kst(2026, 7, 17, 21, 0, 0));
assert.equal(afterLast.live, false);
assert.equal(afterLast.nextSlot.id, 'noise-zero-20260718-17');

// next-day 17:00 -> live
assert.equal(resolveWorldBossSlot(kst(2026, 7, 18, 17, 0, 0)).slot.id, 'noise-zero-20260718-17');

// carry attempts within the same live slot
const sameSlot = normalizeWorldBossProgress({ ...createWorldBossProgress(now), attempts: 2 }, Date.UTC(2026, 6, 17, 8, 40, 0));
assert.equal(sameSlot.attempts, 2, 'attempts carry within the same live slot');

// record past the slot end throws (boundary-crossing guard)
assert.throws(() => recordWorldBossAttempt(progress, 1, kst(2026, 7, 17, 18, 0, 0)), /slot has ended/);

assert.match(worldBossCss, /\.worldboss-core > b:not\(\.worldboss-damage\)/, 'damage number must not inherit the boss-name box');
assert.match(worldBossCss, /\.worldboss-damage \{[^}]*background: transparent;/, 'damage number background stays transparent');
for (const hour of WORLD_BOSS_RULES.scheduleHours) {
  assert.match(worldBossCss, new RegExp(`data-slot-hour="${hour}"`), `${hour}:00 boss image selector must exist`);
}

console.log(`renewal world boss tests passed: 30m raid + 30m result, ${WORLD_BOSS_RULES.maxAttempts} attempts, ${first.totalDamage} first damage, reward ${claimed.reward.points}P, slot ${progress.eventId}`);
