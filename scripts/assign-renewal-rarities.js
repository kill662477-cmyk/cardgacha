const fs = require('fs');
const path = require('path');

const cardsPath = path.join(__dirname, '..', 'data', 'cards.json');
const cards = JSON.parse(fs.readFileSync(cardsPath, 'utf8'));

const rarityOrder = ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS'];
const rarityRank = Object.fromEntries(rarityOrder.map((rarity, index) => [rarity, index]));
const targetCounts = { F: 24, E: 24, D: 24, C: 24, B: 24, A: 24, S: 24, SS: 22 };
const women = new Set(['tomato', 'jidudu', 'haetsal', 'chiri', 'juharang', 'sojuyang', 'imjoy', 'vitaming', 'meonjin', 'arisongi', 'nangni']);
const maleCoaches = new Set(['parkjuno', 'parksubeom', 'sate', 'jidongwon', 'baeseongheum', 'namdeokseon', 'jjiking']);

function prefixFor(card) {
  return card.id.replace(/-\d+$/, '');
}

function hashString(value) {
  let hash = 7;
  for (const character of value) hash = (hash * 31 + character.charCodeAt(0)) >>> 0;
  return hash;
}

function memberBonus(prefix) {
  if (prefix === 'kimyunhwan') return 2;
  if (prefix === 'tomato') return 1.3;
  if (prefix === 'jidudu') return 1.1;
  if (prefix === 'kimmincheol' || prefix === 'byeonhyeonje') return 1.5;
  if (maleCoaches.has(prefix)) return 0.8;
  if (women.has(prefix)) return 0.4;
  return 0;
}

const fixedSssIds = new Set(cards.filter((card) => card.renewalRarity === 'SSS').map((card) => card.id));
const exIds = new Set(cards.filter((card) => card.renewalRarity === 'EX').map((card) => card.id));
const candidates = cards.filter((card) => !fixedSssIds.has(card.id) && !exIds.has(card.id));
const expectedCandidateCount = Object.values(targetCounts).reduce((sum, count) => sum + count, 0);
if (candidates.length !== expectedCandidateCount) {
  throw new Error(`F~SS 재배치 수량 불일치: ${candidates.length}/${expectedCandidateCount}`);
}

for (const card of candidates) {
  const baseline = rarityRank[card.renewalRarity];
  if (baseline === undefined) throw new Error(`재배치 기준 등급 누락: ${card.id}/${card.renewalRarity}`);
  const prefix = prefixFor(card);
  if (!Number.isFinite(card.regradePriority)) {
    card.regradePriority = baseline + memberBonus(prefix) + (hashString(card.id) % 100) / 1000;
  }
  card._score = card.regradePriority;
}

candidates.sort((left, right) => right._score - left._score || left.id.localeCompare(right.id));
let cursor = 0;
for (const rarity of [...rarityOrder].reverse()) {
  const count = targetCounts[rarity];
  for (const card of candidates.slice(cursor, cursor + count)) card.renewalRarity = rarity;
  cursor += count;
}

const requirements = [
  { prefix: 'kimyunhwan', rarity: 'SS', count: 4 },
  { prefix: 'tomato', rarity: 'SS', count: 3 },
  { prefix: 'jidudu', rarity: 'SS', count: 3 },
  { prefix: 'kimmincheol', rarity: 'SS', count: 1 },
  { prefix: 'byeonhyeonje', rarity: 'SS', count: 1 },
  ...[...maleCoaches].map((prefix) => ({ prefix, rarity: 'A', count: 1 })),
];
const exactGrades = {
  'kimyunhwan-7': 'SS',
  'meonjin-13': 'SS',
  'meonjin-14': 'S',
  'sojuyang-14': 'SS',
  'sojuyang-15': 'A',
  'juharang-12': 'SS',
  'jidudu-13': 'SS',
  'chiri-17': 'S',
  'chiri-18': 'A',
  'tomato-14': 'SS',
};
const exactGradeIds = new Set(Object.keys(exactGrades));

function countAtLeast(prefix, rarity, excludingId = null) {
  return candidates.filter((card) => (
    card.id !== excludingId
    && prefixFor(card) === prefix
    && rarityRank[card.renewalRarity] >= rarityRank[rarity]
  )).length;
}

function canDemote(card) {
  if (exactGradeIds.has(card.id)) return false;
  const prefix = prefixFor(card);
  return requirements.every((requirement) => (
    requirement.prefix !== prefix
    || countAtLeast(prefix, requirement.rarity, card.id) >= requirement.count
  ));
}

for (const [id, targetRarity] of Object.entries(exactGrades)) {
  const card = candidates.find((entry) => entry.id === id);
  if (!card) throw new Error(`신규 카드 등급 고정 대상 누락: ${id}`);
  if (card.renewalRarity === targetRarity) continue;
  const previousRarity = card.renewalRarity;
  const donor = candidates
    .filter((entry) => entry.id !== id && !exactGradeIds.has(entry.id) && entry.renewalRarity === targetRarity && canDemote(entry))
    .sort((left, right) => left._score - right._score)[0];
  if (!donor) throw new Error(`신규 카드 등급 맞교환 실패: ${id}/${targetRarity}`);
  card.renewalRarity = targetRarity;
  donor.renewalRarity = previousRarity;
}

for (const requirement of requirements) {
  while (countAtLeast(requirement.prefix, requirement.rarity) < requirement.count) {
    const promote = candidates
      .filter((card) => !exactGradeIds.has(card.id) && prefixFor(card) === requirement.prefix && rarityRank[card.renewalRarity] < rarityRank[requirement.rarity])
      .sort((left, right) => right._score - left._score)[0];
    const demote = candidates
      .filter((card) => !exactGradeIds.has(card.id) && card.renewalRarity === requirement.rarity && prefixFor(card) !== requirement.prefix && canDemote(card))
      .sort((left, right) => left._score - right._score)[0];
    if (!promote || !demote) throw new Error(`상위 배치 보장 실패: ${requirement.prefix}/${requirement.rarity}`);
    const previousRarity = promote.renewalRarity;
    promote.renewalRarity = requirement.rarity;
    demote.renewalRarity = previousRarity;
  }
}

for (const card of candidates) delete card._score;
for (const id of fixedSssIds) {
  const card = cards.find((entry) => entry.id === id);
  if (card.renewalRarity !== 'SSS') throw new Error(`SSS 고정 해제: ${id}`);
}
for (const id of exIds) {
  const card = cards.find((entry) => entry.id === id);
  if (card.renewalRarity !== 'EX') throw new Error(`EX 고정 해제: ${id}`);
}

for (const [rarity, expected] of Object.entries(targetCounts)) {
  const actual = cards.filter((card) => card.renewalRarity === rarity).length;
  if (actual !== expected) throw new Error(`${rarity} 수량 불일치: ${actual}/${expected}`);
}
if (cards.filter((card) => card.renewalRarity === 'SSS').length !== fixedSssIds.size) throw new Error('SSS 수량 변경');

fs.writeFileSync(cardsPath, `${JSON.stringify(cards, null, 2)}\n`, 'utf8');
console.log('F~SS 전면 재배치 완료:', {
  ...targetCounts,
  SSS: fixedSssIds.size,
  EX: exIds.size,
  total: cards.length,
});
