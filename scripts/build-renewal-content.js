const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const sourceCards = JSON.parse(fs.readFileSync(path.join(root, 'data', 'cards.json'), 'utf8'));
const demoCards = JSON.parse(fs.readFileSync(path.join(root, 'data', 'renewal-demo-cards.json'), 'utf8'));
const demoById = new Map(demoCards.map((card) => [card.id, card]));

const races = {
  저그: new Set(['김윤환', '김민철', '박준오', '배성흠', '남덕선', '찌킹', '치리', '임조이', '먼진', '낭니']),
  테란: new Set(['사테', '지동원', '지두두', '햇살', '소주양', '비타밍']),
  프로토스: new Set(['변현제', '박수범', '토마토', '주하랑', '아리송이']),
};
const archetypes = ['quick', 'heavy', 'combo', 'area', 'boss', 'amplify', 'weaken', 'sustain'];
const archetypeCounters = new Map();
const rarityOffsets = new Map(['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'].map((rarity, index) => [rarity, (index * 3) % archetypes.length]));

function raceFor(member, rarity) {
  if (rarity === 'EX') return 'EX';
  return Object.entries(races).find(([, members]) => members.has(member))?.[0] ?? null;
}

function archetypeFor(rarity) {
  if (rarity === 'EX') return null;
  const index = archetypeCounters.get(rarity) ?? 0;
  archetypeCounters.set(rarity, index + 1);
  return archetypes[((rarityOffsets.get(rarity) ?? 0) + index) % archetypes.length];
}

const renewalCards = sourceCards.map((card) => {
  const rarity = card.renewalRarity;
  const starter = demoById.get(card.id);
  return {
    id: card.id,
    member: card.member,
    file: card.file,
    rarity,
    race: raceFor(card.member, rarity),
    archetype: archetypeFor(rarity),
    enhancement: starter?.enhancement ?? 0,
    exp: starter?.exp ?? 0,
    copies: starter ? (starter.copies ?? 1) : 0,
    sourceRarity: card.rarity,
    group: rarity === 'EX',
  };
});

const invalidRace = renewalCards.filter((card) => !card.race);
const missingAssets = renewalCards.filter((card) => !fs.existsSync(path.join(root, 'assets', 'cards', card.file)));
const duplicateIds = renewalCards.filter((card, index) => renewalCards.findIndex((entry) => entry.id === card.id) !== index);
const exCards = renewalCards.filter((card) => card.rarity === 'EX');
if (renewalCards.length !== 212) throw new Error(`Expected 212 cards, got ${renewalCards.length}`);
if (invalidRace.length) throw new Error(`Race missing: ${invalidRace.map((card) => card.id).join(', ')}`);
if (missingAssets.length) throw new Error(`Asset missing: ${missingAssets.map((card) => card.file).join(', ')}`);
if (duplicateIds.length) throw new Error(`Duplicate IDs: ${duplicateIds.map((card) => card.id).join(', ')}`);
if (exCards.length !== 8 || exCards.some((card) => card.member !== '단체사진')) throw new Error('EX must contain the eight group photos only.');
for (const rarity of rarityOffsets.keys()) {
  const counts = archetypes.map((archetype) => renewalCards.filter((card) => card.rarity === rarity && card.archetype === archetype).length);
  if (Math.max(...counts) - Math.min(...counts) > 1 || counts.some((count) => count === 0)) {
    throw new Error(`Archetype distribution is not balanced for ${rarity}: ${counts.join(',')}`);
  }
}

fs.writeFileSync(path.join(root, 'data', 'renewal-cards.json'), `${JSON.stringify(renewalCards, null, 2)}\n`, 'utf8');

const rarityCounts = renewalCards.reduce((counts, card) => {
  counts[card.rarity] = (counts[card.rarity] ?? 0) + 1;
  return counts;
}, {});
const raceCounts = renewalCards.reduce((counts, card) => {
  counts[card.race] = (counts[card.race] ?? 0) + 1;
  return counts;
}, {});
const starterCount = renewalCards.filter((card) => card.copies > 0).length;
console.log(`Renewal content built: ${renewalCards.length} cards, ${starterCount} starter-owned`);
console.log('Rarities:', rarityCounts);
console.log('Races:', raceCounts);
