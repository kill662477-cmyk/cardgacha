const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const stagingDir = 'C:\\Users\\silve\\OneDrive\\Desktop\\card';
const assetsDir = path.join(root, 'assets', 'cards');
const cardsPath = path.join(root, 'data', 'cards.json');

const removals = [
  { id: 'juharang-5', file: 'juharang-5.avif' },
  { id: 'sojuyang-5', file: 'sojuyang-5.avif' },
  { id: 'chiri-10', file: 'chiri-10.png' },
  { id: 'nangni-12', file: 'nangni-12.avif' },
  { id: 'sojuyang-11', file: 'sojuyang-11.avif' },
  { id: 'sojuyang-12', file: 'sojuyang-12.avif' },
  { id: 'jidudu-11', file: 'jidudu-11.avif' },
  { id: 'chiri-15', file: 'chiri-15.avif' },
];

const additions = [
  { id: 'kimyunhwan-7', member: '김윤환', file: 'kimyunhwan-7.avif', source: '김윤환1.avif', rarity: 'MUR', renewalRarity: 'SS' },
  { id: 'meonjin-13', member: '먼진', file: 'meonjin-13.jpeg', source: '먼진.jpeg', rarity: 'MUR', renewalRarity: 'SS' },
  { id: 'meonjin-14', member: '먼진', file: 'meonjin-14.jpeg', source: '먼진1.jpeg', rarity: 'UR', renewalRarity: 'S' },
  { id: 'sojuyang-14', member: '소주양', file: 'sojuyang-14.jpg', source: '소주양.jpg', rarity: 'MUR', renewalRarity: 'SS' },
  { id: 'sojuyang-15', member: '소주양', file: 'sojuyang-15.jpg', source: '소주양1.jpg', rarity: 'UR', renewalRarity: 'S' },
  { id: 'juharang-12', member: '주하랑', file: 'juharang-12.webp', source: '주하랑.webp', rarity: 'MUR', renewalRarity: 'SS' },
  { id: 'jidudu-13', member: '지두두', file: 'jidudu-13.jpg', source: '지두두.jpg', rarity: 'MUR', renewalRarity: 'SS' },
  { id: 'chiri-17', member: '치리', file: 'chiri-17.avif', source: '치리.avif', rarity: 'MUR', renewalRarity: 'SS' },
  { id: 'chiri-18', member: '치리', file: 'chiri-18.jpg', source: '치리1.jpg', rarity: 'UR', renewalRarity: 'S' },
  { id: 'tomato-14', member: '토마토', file: 'tomato-14.png', source: '캡처_2026_07_18_20_08_00_766.png', rarity: 'MUR', renewalRarity: 'SS' },
];

const cards = JSON.parse(fs.readFileSync(cardsPath, 'utf8'));
const removalIds = new Set(removals.map(({ id }) => id));
const additionIds = new Set(additions.map(({ id }) => id));
const missingRemovalIds = [...removalIds].filter((id) => !cards.some((card) => card.id === id));
if (missingRemovalIds.length && !missingRemovalIds.every((id) => additionIds.has(id))) {
  console.warn(`이미 제거된 카드: ${missingRemovalIds.join(', ')}`);
}

const retained = cards.filter((card) => !removalIds.has(card.id) && !additionIds.has(card.id));
for (const addition of additions) {
  const sourcePath = path.join(stagingDir, addition.source);
  if (!fs.existsSync(sourcePath)) throw new Error(`신규 사진 누락: ${addition.source}`);
  fs.copyFileSync(sourcePath, path.join(assetsDir, addition.file));
  retained.push({
    id: addition.id,
    member: addition.member,
    file: addition.file,
    rarity: addition.rarity,
    renewalRarity: addition.renewalRarity,
  });
}

for (const removal of removals) {
  const assetPath = path.resolve(assetsDir, removal.file);
  if (!assetPath.startsWith(`${path.resolve(assetsDir)}${path.sep}`)) throw new Error(`잘못된 삭제 경로: ${assetPath}`);
  if (fs.existsSync(assetPath)) fs.unlinkSync(assetPath);
}
const staleAsset = path.join(assetsDir, 'chiri-17.jpg');
if (fs.existsSync(staleAsset)) fs.unlinkSync(staleAsset);

if (new Set(retained.map((card) => card.id)).size !== retained.length) throw new Error('카드 ID 중복');
fs.writeFileSync(cardsPath, `${JSON.stringify(retained, null, 2)}\n`, 'utf8');
console.log(`카드 staging 반영: -${removals.length}, +${additions.length}, 총 ${retained.length}장`);
