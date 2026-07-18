import assert from 'node:assert/strict';
import {
  canFastForwardPackPhase,
  enhancementFxTier,
  enhancementTimeline,
  highestCinematicRarity,
  packOpeningTimeline,
  requiresManualPackReveal,
  selectManualPackRevealCards,
  selectPackRevealCards,
  selectRarityCinematic,
} from '../src/renewal/fx-controller.js';
import { DEFAULT_STATE } from '../src/renewal/storage.js';

function totalDuration(timeline) {
  return timeline.reduce((sum, step) => sum + step.duration, 0);
}

const success = enhancementTimeline('success');
const fail = enhancementTimeline('fail');
const destroy = enhancementTimeline('destroy');
const reduced = enhancementTimeline('success', true);

assert.deepEqual(success.map((step) => step.phase), ['charge', 'impact', 'result', 'settle']);
assert.deepEqual(fail.map((step) => step.phase), ['charge', 'impact', 'result', 'settle']);
assert.ok(totalDuration(fail) < totalDuration(success));
assert.ok(totalDuration(success) >= 3000);
assert.ok(totalDuration(success) > totalDuration(destroy));
assert.ok(totalDuration(reduced) <= 250);
assert.deepEqual(reduced.map((step) => step.phase), ['impact', 'result']);
assert.deepEqual([1, 3, 4, 6, 7, 8, 9].map(enhancementFxTier), ['standard', 'standard', 'advanced', 'advanced', 'elite', 'elite', 'max']);

const singlePack = packOpeningTimeline(4);
const bulkPack = packOpeningTimeline(10);
const reducedPack = packOpeningTimeline(10, true);
assert.equal(singlePack.reveal, 150);
assert.equal(bulkPack.reveal, 95);
const reducedPackDuration = reducedPack.approach + reducedPack.charge + reducedPack.burst + reducedPack.reveal * 10 + reducedPack.summary;
assert.ok(reducedPackDuration <= 450);

const revealCards = selectPackRevealCards([
  { name: 'F-1', rank: 0 },
  { name: 'S-1', rank: 6 },
  { name: 'A-1', rank: 5 },
  { name: 'SSS-1', rank: 8 },
  { name: 'E-1', rank: 1 },
], 3);
assert.deepEqual(revealCards.map((card) => card.name), ['SSS-1', 'S-1', 'A-1']);

const manualRevealCards = selectManualPackRevealCards([
  { name: 'A-1', rarity: 'A', rank: 5 },
  { name: 'S-1', rarity: 'S', rank: 6 },
  { name: 'F-1', rarity: 'F', rank: 0 },
  { name: 'SSS-1', rarity: 'SSS', rank: 8 },
]);
assert.deepEqual(manualRevealCards.map((card) => card.name), ['S-1', 'SSS-1']);

assert.equal(highestCinematicRarity([{ rarity: 'A' }, { rarity: 'S' }, { rarity: 'SS' }]), 'SS');
assert.equal(highestCinematicRarity([{ rarity: 'F' }, { rarity: 'A' }]), null);
assert.equal(selectRarityCinematic([{ rarity: 'S' }, { rarity: 'SSS' }]).rarity, 'SSS');
assert.equal(selectRarityCinematic([{ rarity: 'SSS' }], true), null);
assert.equal(requiresManualPackReveal([{ rarity: 'A' }, { rarity: 'SS' }]), true);
assert.equal(requiresManualPackReveal([{ rarity: 'F' }, { rarity: 'A' }]), false);
assert.equal(canFastForwardPackPhase('pack-approach'), true);
assert.equal(canFastForwardPackPhase('pack-rarity'), true);
assert.equal(canFastForwardPackPhase('pack-reveal'), false);
assert.equal(DEFAULT_STATE.soundEnabled, true);

console.log('renewal fx tests passed: enhancement, pack timeline, high-rarity manual reveal');
