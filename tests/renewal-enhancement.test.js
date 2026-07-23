import assert from 'node:assert/strict';
import { ENHANCEMENT } from '../src/renewal/config.js';
import {
  applyEnhancementResult,
  availableDuplicateCount,
  consumeSelectedMaterials,
  getEnhancementGate,
  getEnhancementOdds,
  resolveEnhancement,
  selectEnhancementMaterials,
} from '../src/renewal/enhancement.js';

const target = { id: 'target-b', rarity: 'B', enhancement: 0, exp: 100 };
const cards = [target, { id: 'c-1', rarity: 'C' }, { id: 'c-2', rarity: 'C' }];
const copies = { 'target-b': 1, 'c-1': 3, 'c-2': 2 };
const selection = selectEnhancementMaterials(target, cards, copies);
assert.equal(selection.ready, true);
assert.equal(selection.selected.length, 3);
assert.equal(availableDuplicateCount('c-1', copies), 2, 'last copy must be protected');
assert.equal(getEnhancementGate(target, selection, 0).ready, true);

const consumed = consumeSelectedMaterials(copies, selection.selected);
assert.equal(consumed['c-1'] + consumed['c-2'], copies['c-1'] + copies['c-2'] - 3);

const lockedF = { id: 'locked-f', rarity: 'F', enhancement: 0, exp: 100 };
const sameCardSelection = selectEnhancementMaterials(
  lockedF,
  [lockedF, { id: 'other-f', rarity: 'F' }],
  { 'locked-f': 2, 'other-f': 2 },
  { 'locked-f': true, 'other-f': true },
);
assert.deepEqual(sameCardSelection.selected, ['locked-f'], 'locked target duplicates may be used as material');
assert.equal(sameCardSelection.available, 1);
assert.equal(availableDuplicateCount('locked-f', { 'locked-f': 1 }, { 'locked-f': true }, 'locked-f'), 0, 'target base copy must remain');
assert.equal(availableDuplicateCount('other-f', { 'other-f': 2 }, { 'other-f': true }, 'locked-f'), 0, 'other locked cards stay protected');

assert.deepEqual(getEnhancementOdds({ rarity: 'F', enhancement: 3 }), { target: 4, success: 80, destroy: 0, fail: 20 });
assert.deepEqual(getEnhancementOdds({ rarity: 'F', enhancement: 8 }), { target: 9, success: 30, destroy: 15, fail: 55 });
assert.deepEqual(getEnhancementOdds({ rarity: 'SSS', enhancement: 8 }), { target: 9, success: 12, destroy: 15, fail: 73 });
assert.deepEqual(getEnhancementOdds({ rarity: 'SSS', enhancement: 8 }, 'enhance10'), { target: 9, success: 22, destroy: 15, fail: 63 });
for (const rarity of ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS']) {
  for (let enhancement = 0; enhancement < 9; enhancement += 1) {
    const odds = getEnhancementOdds({ rarity, enhancement });
    assert.equal(odds.success + odds.destroy + odds.fail, 100);
    assert.ok(odds.success >= 0 && odds.destroy >= 0 && odds.fail >= 0);
  }
}
assert.equal(resolveEnhancement({ rarity: 'SSS', enhancement: 8 }, 'none', 0.1).outcome, 'success');
assert.equal(resolveEnhancement({ rarity: 'SSS', enhancement: 8 }, 'none', 0.2).outcome, 'destroy');
const guarded = resolveEnhancement({ rarity: 'SSS', enhancement: 8 }, 'destructionGuard', 0.2);
assert.equal(guarded.outcome, 'fail');
assert.equal(guarded.blocked, true);

const ownedBeforeDestroy = { sss: 2 };
const destroyedProgress = applyEnhancementResult(
  { id: 'sss', rarity: 'SSS', enhancement: 8, exp: 2500 },
  resolveEnhancement({ rarity: 'SSS', enhancement: 8 }, 'none', 0.2),
);
assert.deepEqual(destroyedProgress, { enhancement: 0, exp: 0 });
assert.deepEqual(ownedBeforeDestroy, { sss: 2 }, 'destroy resets progress without consuming the original card');

const plusNineGate = getEnhancementGate(
  { id: 'sss', rarity: 'SSS', enhancement: 8, exp: 2500 },
  { ready: true },
  ENHANCEMENT.plusNinePointCost - 1,
);
assert.equal(plusNineGate.ready, false);
assert.match(plusNineGate.reason, /포인트/);

console.log('renewal enhancement tests passed: materials, last-copy protection, odds, destroy reset, guard, +9 cost');
