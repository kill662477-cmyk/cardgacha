/*
 * 가챠 핵심 로직 + 공용 헬퍼. 서버리스 함수들이 공유한다.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const RARITIES = ['C', 'U', 'R', 'RR', 'RRR', 'AR', 'CHR', 'HR', 'SR', 'SAR', 'UR', 'MUR', 'FUR'];
const RANK = Object.fromEntries(RARITIES.map((r, i) => [r, i]));

// ---- cards.json 로드 (한 번만) ----
let CARDS = null;
let POOL = null; // rarity -> [card]
function loadCards() {
  if (CARDS) return CARDS;
  const file = path.resolve(__dirname, '..', 'data', 'cards.json');
  CARDS = JSON.parse(fs.readFileSync(file, 'utf8'));
  POOL = {};
  for (const r of RARITIES) POOL[r] = [];
  for (const c of CARDS) POOL[c.rarity].push(c);
  return CARDS;
}

// ---- 팩 정의 ----
const PACKS = {
  normal: {
    id: 'normal', name: '일반팩', price: 50, count: 3, guarantee: null,
    odds: { C: 45, U: 25, R: 14, RR: 7, RRR: 4, AR: 2, CHR: 1.2, HR: 0.8, SR: 0.5, SAR: 0.25, UR: 0.15, MUR: 0.07, FUR: 0.03 },
  },
  premium: {
    id: 'premium', name: '고급팩', price: 150, count: 4, guarantee: 'R',
    odds: { C: 25, U: 22, R: 20, RR: 12, RRR: 8, AR: 5, CHR: 3, HR: 2, SR: 1.5, SAR: 0.8, UR: 0.4, MUR: 0.2, FUR: 0.1 },
  },
  luxury: {
    id: 'luxury', name: '프리미엄팩', price: 500, count: 5, guarantee: 'SR',
    odds: { C: 10, U: 15, R: 18, RR: 15, RRR: 12, AR: 9, CHR: 7, HR: 5, SR: 4, SAR: 2.5, UR: 1.5, MUR: 0.7, FUR: 0.3 },
  },
};

// ---- 중복 분해 환급표 (rarity -> P) ----
const DISMANTLE_REFUND = {
  C: 5, U: 8, R: 15, RR: 25, RRR: 40, AR: 60, CHR: 80, HR: 100,
  SR: 130, SAR: 170, UR: 220, MUR: 300, FUR: 400,
};

// id -> card 조회 맵 (한 번만 빌드)
let BY_ID = null;
function cardById(id) {
  loadCards();
  if (!BY_ID) {
    BY_ID = {};
    for (const c of CARDS) BY_ID[c.id] = c;
  }
  return BY_ID[id] || null;
}

function secureRandom() {
  // 0..1 암호학적 난수 (뽑기 조작 방지)
  return crypto.randomBytes(4).readUInt32BE(0) / 4294967296;
}

function rollRarity(odds) {
  const entries = Object.entries(odds);
  const total = entries.reduce((s, [, w]) => s + w, 0);
  let r = secureRandom() * total;
  for (const [grade, w] of entries) {
    r -= w;
    if (r <= 0) return grade;
  }
  return entries[entries.length - 1][0];
}

// 등급 -> 카드 (풀 비면 한 단계 아래로 폴백)
function pickCardOfRarity(rarity) {
  loadCards();
  let idx = RANK[rarity];
  while (idx >= 0) {
    const pool = POOL[RARITIES[idx]];
    if (pool && pool.length) {
      return pool[Math.floor(secureRandom() * pool.length)];
    }
    idx--; // 폴백
  }
  // 이론상 도달 불가
  return CARDS[0];
}

// 보장 등급 이상으로 롤 (guarantee 이상 나올 때까지 재롤, 안전 상한)
function rollGuaranteed(odds, minRarity) {
  const min = RANK[minRarity];
  // 보장 등급 이상만 남긴 가중치로 롤
  const filtered = {};
  for (const [g, w] of Object.entries(odds)) {
    if (RANK[g] >= min) filtered[g] = w;
  }
  if (Object.keys(filtered).length === 0) return minRarity;
  return rollRarity(filtered);
}

function openPack(packId) {
  const pack = PACKS[packId];
  if (!pack) throw new Error('unknown pack');
  loadCards();
  const drawn = [];
  for (let i = 0; i < pack.count; i++) {
    const isLast = i === pack.count - 1;
    let rarity;
    if (isLast && pack.guarantee) {
      rarity = rollGuaranteed(pack.odds, pack.guarantee);
    } else {
      rarity = rollRarity(pack.odds);
    }
    const card = pickCardOfRarity(rarity);
    drawn.push(card);
  }
  return drawn;
}

// ---- 공용: Asia/Seoul 오늘 날짜 (YYYY-MM-DD) ----
function seoulToday() {
  const now = new Date();
  // UTC+9
  const seoul = new Date(now.getTime() + 9 * 3600 * 1000);
  return seoul.toISOString().slice(0, 10);
}

// ---- 공용: 로그인 키 생성 (32자 hex) ----
function newKey() {
  return crypto.randomBytes(16).toString('hex');
}

module.exports = {
  RARITIES, RANK, PACKS, DISMANTLE_REFUND,
  loadCards,
  cardById,
  openPack,
  seoulToday,
  newKey,
  getCards: () => loadCards(),
};
