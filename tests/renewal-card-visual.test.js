import assert from 'node:assert/strict';
import {
  cardFramePath,
  cardVisualChrome,
  enhancementLabel,
  enhancementStarMarkup,
  enhancementTier,
  normalizeEnhancement,
} from '../src/renewal/card-visual.js';

assert.equal(normalizeEnhancement(-3), 0);
assert.equal(normalizeEnhancement(12), 9);
assert.equal(enhancementLabel(3), '3성');
assert.deepEqual([0, 1, 4, 7, 9].map(enhancementTier), ['zero', 'low', 'mid', 'high', 'max']);
assert.equal(cardFramePath('SSS'), 'assets/renewal/card-frames/card-frame-sss.webp');
assert.equal(cardFramePath('EX'), 'assets/renewal/card-frames/card-frame-ex.webp');
assert.equal(enhancementStarMarkup(0), '');

const star = enhancementStarMarkup(7);
assert.match(star, /enhancement-star\.webp/);
assert.match(star, /×7/);
assert.match(star, /7성 강화/);
assert.doesNotMatch(star, /\+7/);

const max = cardVisualChrome({ rarity: 'SSS', enhancement: 9 });
assert.match(max, /card-frame-sss\.webp/);
assert.match(max, /data-rarity="SSS"/);
assert.match(max, /data-star-tier="max"/);
assert.match(max, /MAX/);

console.log('renewal card visual tests passed: rarity core, star ranks, frame mapping');
