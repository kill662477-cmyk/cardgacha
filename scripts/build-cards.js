/*
 * build-cards.js
 * card 폴더의 원본 87장을 assets/cards/ 로 ASCII 파일명으로 복사하고
 * data/cards.json 을 생성한다. 시드 고정이라 재실행해도 결과 동일.
 * 원본 폴더(C:\Users\silve\OneDrive\Desktop\card)는 절대 수정하지 않는다.
 */
const fs = require('fs');
const path = require('path');

// ---- 경로 ----
const SRC_DIR = process.env.CARD_SRC || 'C:\\Users\\silve\\OneDrive\\Desktop\\card';
const ROOT = path.resolve(__dirname, '..');
const OUT_ASSETS = path.join(ROOT, 'assets', 'cards');
const OUT_JSON = path.join(ROOT, 'data', 'cards.json');

// ---- 등급 (낮음→높음) ----
const RARITIES = ['C', 'U', 'R', 'RR', 'RRR', 'AR', 'CHR', 'HR', 'SR', 'SAR', 'UR', 'MUR', 'FUR'];

// ---- 멤버 로마자 매핑 (ASCII 안전 파일명용) ----
const ROMAN = {
  '김윤환': 'kimyunhwan',
  '김민철': 'kimmincheol',
  '변현제': 'byeonhyeonje',
  '사테': 'sate',
  '박준오': 'parkjuno',
  '박수범': 'parksubeom',
  '지동원': 'jidongwon',
  '배성흠': 'baeseongheum',
  '남덕선': 'namdeokseon',
  '토마토': 'tomato',
  '지두두': 'jidudu',
  '햇살': 'haetsal',
  '찌킹': 'jjiking',
  '치리': 'chiri',
  '주하랑': 'juharang',
  '소주양': 'sojuyang',
  '임조이': 'imjoy',
  '비타밍': 'vitaming',
  '먼진': 'meonjin',
  '아리송이': 'arisongi',
  '낭니': 'nangni',
};

// 남자 코치 7명 = C/U/R 하위등급만
const MALE_COACHES = new Set(['변현제', '김민철', '사테', '박준오', '박수범', '지동원', '배성흠']);

// ---- 시드 고정 RNG (mulberry32) ----
function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rng = mulberry32(20260711); // 고정 시드

function pickWeighted(rand, entries) {
  // entries: [[value, weight], ...]
  const total = entries.reduce((s, e) => s + e[1], 0);
  let r = rand() * total;
  for (const [val, w] of entries) {
    r -= w;
    if (r <= 0) return val;
  }
  return entries[entries.length - 1][0];
}

// ---- 원본 파일 스캔 ----
const files = fs.readdirSync(SRC_DIR).filter(f => /\.(avif|webp|jpg|jpeg|png)$/i.test(f));

function parse(fileName) {
  const ext = path.extname(fileName);
  const base = fileName.slice(0, -ext.length);
  const m = base.match(/^(.+?)(\d*)$/); // 이름 + 끝 숫자
  const member = m[1];
  const suffix = m[2]; // '' 또는 '1'..'n'
  return { member, suffix, ext: ext.toLowerCase() };
}

// 멤버별로 그룹화 (원본 파일명 정렬로 결정론적 인덱스)
const byMember = {};
for (const f of files.sort()) {
  const { member, suffix, ext } = parse(f);
  if (!ROMAN[member]) {
    console.warn('경고: 매핑 없는 멤버 파일 스킵 ->', f);
    continue;
  }
  (byMember[member] = byMember[member] || []).push({ file: f, suffix, ext });
}

// ---- 등급 배정 ----
// 1) 결정론적 셔플용 헬퍼
function shuffle(arr, rand) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const cards = [];
let idCounter = {};

// 여성(비고정) 카드 풀 수집 -> 나중에 일괄 가중 배정
const womenPool = [];

for (const member of Object.keys(byMember)) {
  const roman = ROMAN[member];
  const list = byMember[member];
  idCounter[member] = 0;
  for (const item of list) {
    idCounter[member] += 1;
    const idx = idCounter[member];
    const newFile = `${roman}-${idx}${item.ext}`;
    const id = `${roman}-${idx}`;
    const card = { id, member, file: newFile, rarity: null, _src: item.file, _suffix: item.suffix };

    // 고정 규칙
    if (member === '김윤환') {
      card.rarity = 'FUR'; // 규칙1
    } else if (member === '소주양' && item.suffix === '1') {
      card.rarity = 'FUR'; // 규칙2
    } else if (member === '지두두' && item.suffix === '1') {
      card.rarity = 'FUR'; // 규칙2
    } else if (MALE_COACHES.has(member)) {
      card.rarity = pickWeighted(rng, [['C', 50], ['U', 30], ['R', 20]]); // 규칙3
    } else {
      // 규칙4: 여성 비고정 -> 나중에 가중 배정
      womenPool.push(card);
    }
    cards.push(card);
  }
}

// ---- 규칙4: 여성 비고정 카드 가중 배정 (각 등급 최소 1장 보장) ----
// 가중치: 하위 흔함, 상위 드묾
const WEIGHTS = {
  C: 30, U: 22, R: 16, RR: 11, RRR: 7, AR: 5, CHR: 3.5,
  HR: 2.5, SR: 1.8, SAR: 1.2, UR: 0.8, MUR: 0.5, FUR: 0.3,
};

const shuffledWomen = shuffle(womenPool, rng);
// 1단계: 앞의 13장을 13등급에 1장씩 (각 상위등급 최소 1장 보장)
const gradeOrder = shuffle(RARITIES, rng); // 어느 카드가 어느 등급인지 무작위화
for (let i = 0; i < shuffledWomen.length; i++) {
  if (i < RARITIES.length) {
    shuffledWomen[i].rarity = gradeOrder[i];
  } else {
    // 2단계: 나머지는 가중 랜덤 (하위 흔함)
    shuffledWomen[i].rarity = pickWeighted(rng, RARITIES.map(r => [r, WEIGHTS[r]]));
  }
}

// ---- 이미지 복사 ----
if (!fs.existsSync(OUT_ASSETS)) fs.mkdirSync(OUT_ASSETS, { recursive: true });
for (const c of cards) {
  const src = path.join(SRC_DIR, c._src);
  const dst = path.join(OUT_ASSETS, c.file);
  fs.copyFileSync(src, dst);
}

// ---- 카드 뒷면 로고 복사 (assets/card-back.png 하나로 통일) ----
// 사용자 고화질 파일이 있으면 우선, 없으면 monstarznew 파비콘으로 폴백.
const OUT_ASSETS_ROOT = path.join(ROOT, 'assets');
const BACK_DST = path.join(OUT_ASSETS_ROOT, 'card-back.png');
const BACK_USER = 'C:\\Users\\silve\\OneDrive\\Desktop\\card-back.png';
const BACK_FALLBACK = 'C:\\Users\\silve\\OneDrive\\Desktop\\MONSTARZNEW_PROJECT_REPOS_20260617-104902\\monstarznew\\assets\\monstarz-favicon-512.png';
let backSrc = null;
if (fs.existsSync(BACK_USER)) backSrc = BACK_USER;
else if (fs.existsSync(BACK_FALLBACK)) backSrc = BACK_FALLBACK;
if (backSrc) {
  fs.copyFileSync(backSrc, BACK_DST);
  console.log('카드 뒷면 로고 ->', backSrc === BACK_USER ? '사용자 고화질본' : '폴백(파비콘)');
} else {
  console.warn('경고: 카드 뒷면 로고 원본을 찾지 못했습니다. assets/card-back.png 수동 배치 필요');
}

// ---- cards.json 기록 (내부 필드 제거) ----
const clean = cards
  .map(c => ({ id: c.id, member: c.member, file: c.file, rarity: c.rarity }))
  .sort((a, b) => a.id.localeCompare(b.id));

fs.writeFileSync(OUT_JSON, JSON.stringify(clean, null, 2), 'utf8');

// ---- 검증 리포트 ----
const dist = {};
for (const r of RARITIES) dist[r] = 0;
for (const c of clean) dist[c.rarity]++;

const kimyunhwan = clean.filter(c => c.member === '김윤환');
const allFur = kimyunhwan.every(c => c.rarity === 'FUR');
const soju1 = cards.find(c => c.member === '소주양' && c._suffix === '1');
const jidudu1 = cards.find(c => c.member === '지두두' && c._suffix === '1');

console.log('=== 카드 빌드 완료 ===');
console.log('총 카드 수:', clean.length);
console.log('등급 분포:');
for (const r of RARITIES) console.log(`  ${r.padEnd(4)} : ${dist[r]}`);
console.log('김윤환 5장 전부 FUR:', allFur, `(${kimyunhwan.length}장)`);
console.log('소주양1 == FUR:', soju1 && soju1.rarity === 'FUR');
console.log('지두두1 == FUR:', jidudu1 && jidudu1.rarity === 'FUR');
console.log('모든 등급 최소 1장:', RARITIES.every(r => dist[r] >= 1));
console.log('cards.json ->', OUT_JSON);
