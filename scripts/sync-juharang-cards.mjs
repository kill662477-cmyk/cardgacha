import { access, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cardsPath = path.join(root, 'data', 'renewal-cards.json');
const reviewDir = path.join(root, 'aether-output', 'juharang-20260723');
const archetypes = ['quick', 'heavy', 'combo', 'area', 'boss', 'amplify', 'weaken', 'sustain'];
const cardIds = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17];
const rarities = new Map([
  [1, 'C'], [2, 'SSS'], [3, 'SS'], [4, 'SS'], [5, 'D'], [6, 'S'],
  [7, 'A'], [8, 'C'], [9, 'B'], [10, 'F'], [11, 'F'], [12, 'E'],
  [13, 'E'], [14, 'D'], [16, 'A'], [17, 'S'],
]);
const sourceRarity = {
  F: 'U', E: 'RR', D: 'RRR', C: 'R', B: 'SR', A: 'SAR', S: 'UR', SS: 'MUR', SSS: 'FUR',
};

await Promise.all(cardIds.map((id) => access(path.join(reviewDir, `juharang-${id}.webp`))));

const cards = JSON.parse(await readFile(cardsPath, 'utf8'));
const existingIndexes = cards
  .map((card, index) => (card.id.startsWith('juharang-') ? index : -1))
  .filter((index) => index >= 0);
if (existingIndexes.length !== 11) throw new Error(`Expected 11 existing Juharang cards, found ${existingIndexes.length}`);
const insertAt = Math.min(...existingIndexes);
const existingById = new Map(cards.filter((card) => card.id.startsWith('juharang-')).map((card) => [card.id, card]));
const retained = cards.filter((card) => !card.id.startsWith('juharang-'));

const archetypeCounts = new Map();
for (const card of retained) {
  if (card.rarity === 'EX') continue;
  if (!archetypeCounts.has(card.rarity)) archetypeCounts.set(card.rarity, new Map(archetypes.map((id) => [id, 0])));
  const counts = archetypeCounts.get(card.rarity);
  counts.set(card.archetype, (counts.get(card.archetype) ?? 0) + 1);
}

function nextArchetype(rarity) {
  if (!archetypeCounts.has(rarity)) archetypeCounts.set(rarity, new Map(archetypes.map((id) => [id, 0])));
  const counts = archetypeCounts.get(rarity);
  const selected = [...archetypes].sort((left, right) => counts.get(left) - counts.get(right))[0];
  counts.set(selected, counts.get(selected) + 1);
  return selected;
}

const replacements = cardIds.map((number) => {
  const id = `juharang-${number}`;
  const previous = existingById.get(id);
  const rarity = rarities.get(number);
  return {
    id,
    member: '주하랑',
    file: `${id}.webp`,
    rarity,
    race: '프로토스',
    archetype: nextArchetype(rarity),
    enhancement: previous?.enhancement ?? 0,
    exp: previous?.exp ?? 0,
    copies: previous?.copies ?? 0,
    sourceRarity: sourceRarity[rarity],
    group: false,
  };
});

retained.splice(insertAt, 0, ...replacements);
if (retained.length !== 219) throw new Error(`Expected 219 cards, found ${retained.length}`);
if (new Set(retained.map((card) => card.id)).size !== retained.length) throw new Error('Duplicate card ID');
if (retained.some((card) => card.id === 'juharang-15')) throw new Error('juharang-15 must remain excluded');

await writeFile(cardsPath, `${JSON.stringify(retained, null, 2)}\n`, 'utf8');
console.log('Juharang catalog synchronized:', Object.fromEntries(replacements.map((card) => [card.id, card.rarity])));
