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
    odds: { C: 45, U: 25, R: 14, RR: 7, RRR: 4, AR: 2, CHR: 1.2, HR: 0.8, SR: 0.25, SAR: 0.125, UR: 0.075, MUR: 0.035, FUR: 0.015 },
  },
  premium: {
    id: 'premium', name: '고급팩', price: 150, count: 4, guarantee: 'R',
    odds: { C: 25, U: 22, R: 20, RR: 12, RRR: 8, AR: 5, CHR: 3, HR: 2, SR: 0.75, SAR: 0.4, UR: 0.2, MUR: 0.1, FUR: 0.05 },
  },
  luxury: {
    id: 'luxury', name: '프리미엄팩', price: 500, count: 5, guarantee: 'SR',
    odds: { C: 10, U: 15, R: 18, RR: 15, RRR: 12, AR: 9, CHR: 7, HR: 5, SR: 2, SAR: 1.25, UR: 0.75, MUR: 0.35, FUR: 0.15 },
  },
};

// ---- 중복 분해 환급표 (rarity -> P, 최대 250) ----
const DISMANTLE_REFUND = {
  C: 5, U: 8, R: 12, RR: 20, RRR: 30, AR: 45, CHR: 60, HR: 80,
  SR: 100, SAR: 130, UR: 160, MUR: 200, FUR: 250,
};

// ---- 합성 성공률 (재료 등급 -> 성공 %, FUR 은 최상위이므로 합성 불가) ----
const FUSE_RATES = {
  C: 90, U: 85, R: 80, RR: 75, RRR: 70, AR: 60, CHR: 55, HR: 50,
  SR: 40, SAR: 35, UR: 25, MUR: 1,
};

// 합성 재료 3장 소모. 성공률(secureRandom) 판정 + 결과카드/위로보상 선정.
// 성공: 한 단계 위 등급 풀에서 균등 랜덤 카드 1장 (풀 비면 한 단계 위로 폴백)
// 실패: 위로 포인트 = DISMANTLE_REFUND[재료등급] * 3 * 50% (내림)
function nextRarity(rarity) {
  const idx = RANK[rarity];
  if (idx == null || idx >= RARITIES.length - 1) return null;
  return RARITIES[idx + 1];
}

function fuseConsolation(rarity) {
  const base = DISMANTLE_REFUND[rarity] || 0;
  return Math.floor((base * 3) / 2);
}

// 결과 등급 풀에서 균등 랜덤. 풀이 비면 한 단계 위 등급으로 폴백(올림).
function pickFuseResult(materialRarity) {
  const up = nextRarity(materialRarity);
  if (!up) return null;
  loadCards();
  let idx = RANK[up];
  while (idx < RARITIES.length) {
    const pool = POOL[RARITIES[idx]];
    if (pool && pool.length) return pool[Math.floor(secureRandom() * pool.length)];
    idx++; // 폴백: 한 단계 위로
  }
  return null;
}

// 재료 등급으로 합성 1회 판정. 합성 불가 등급이면 null.
function resolveFuse(materialRarity) {
  const rate = FUSE_RATES[materialRarity];
  if (rate == null) return null; // FUR 등 합성 불가
  const success = secureRandom() * 100 < rate;
  if (success) {
    const card = pickFuseResult(materialRarity);
    if (!card) return null; // 결과 풀이 전혀 없음(이론상 도달 불가)
    return { success: true, rate, card };
  }
  return { success: false, rate, consolation: fuseConsolation(materialRarity) };
}

// ---- 멤버 도감 완성 보상표 (member -> P, 난이도별 차등) ----
// 카드 수와 재배치된 최고 등급을 반영한다. 멤버명은 cards.json 과 정확히 일치해야 한다.
const MEMBER_REWARDS = {
  '김윤환': 1000, '토마토': 900, '지두두': 850, '치리': 750, '비타밍': 650,
  '주하랑': 550, '임조이': 500, '햇살': 400, '소주양': 400, '낭니': 400,
  '먼진': 400, '찌킹': 300, '아리송이': 250, '변현제': 250, '김민철': 250,
  '남덕선': 200, '박준오': 150, '지동원': 150, '배성흠': 150, '박수범': 150,
  '사테': 150,
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
  RARITIES, RANK, PACKS, DISMANTLE_REFUND, MEMBER_REWARDS, FUSE_RATES,
  loadCards,
  cardById,
  openPack,
  nextRarity,
  fuseConsolation,
  pickFuseResult,
  resolveFuse,
  seoulToday,
  newKey,
  getCards: () => loadCards(),
};
