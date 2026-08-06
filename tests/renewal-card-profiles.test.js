import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  ARCHETYPES, CARD_PROFILES, CARD_PROFILE_DESCRIPTIONS, ENHANCEMENT, GAME_RULES, RARITIES,
} from '../src/renewal/config.js';
import { cardProfileOf, computeCardStats } from '../src/renewal/battle.js';

const cards = JSON.parse(await readFile(new URL('../data/renewal-cards.json', import.meta.url), 'utf8'));
const combatCards = cards.filter((card) => card.rarity !== 'EX' && card.archetype);
const archetypeKeys = Object.keys(ARCHETYPES);

// --- 구성 ---
// 첫 프로필은 보정 없는 기준이어야 한다. 여기가 흔들리면 scale 계산의 원점이 사라진다.
assert.equal(CARD_PROFILES[0].key, 'balanced');
assert.equal(CARD_PROFILES[0].scale, 1);
for (const field of ['atk', 'hp', 'def', 'speed']) assert.equal(CARD_PROFILES[0][field], 1);
for (const field of ['crit', 'critDamage']) assert.equal(CARD_PROFILES[0][field], 0);

const keys = CARD_PROFILES.map((profile) => profile.key);
assert.equal(new Set(keys).size, keys.length, '프로필 key 가 겹치면 안 된다');
for (const profile of CARD_PROFILES) {
  for (const field of ['atk', 'hp', 'def', 'speed', 'crit', 'critDamage', 'scale']) {
    assert.ok(Number.isFinite(profile[field]), `${profile.key}.${field} 가 숫자가 아니다`);
  }
  assert.ok(profile.label, `${profile.key} 에 표시 이름이 없다`);
  // 설명이 없으면 카드 상세에 undefined 가 찍힌다.
  assert.ok(CARD_PROFILE_DESCRIPTIONS[profile.key], `${profile.key} 설명이 없다`);
}

// --- 균등성: 프로필은 배분만 바꾸고 세기는 바꾸지 않는다 ---
// 여기가 무너지면 프로필이 우열이 되고, 뽑기 운으로 카드 강함이 갈린다.
function statsFor(archetypeKey, profile) {
  const base = GAME_RULES.baseCardStats;
  const archetype = ARCHETYPES[archetypeKey];
  const common = RARITIES.S.multiplier * ENHANCEMENT.statMultipliers[5] * profile.scale;
  return {
    atk: Math.round(base.atk * common * (archetype.atk ?? 1) * profile.atk),
    hp: Math.round(base.hp * common * (archetype.hp ?? 1) * profile.hp),
    def: Math.round(base.def * common * (archetype.def ?? 1) * profile.def),
    speed: Number((base.speed * (archetype.speed ?? 1) * profile.speed).toFixed(2)),
    crit: Number(Math.min(0.6, base.crit + (archetype.crit ?? 0) + profile.crit).toFixed(3)),
    critDamage: Number((base.critDamage + (archetype.critDamage ?? 0) + profile.critDamage).toFixed(2)),
  };
}

function damageFor(archetypeKey, profile) {
  const stats = statsFor(archetypeKey, profile);
  const trait = ARCHETYPES[archetypeKey];
  const dps = (boss) => {
    const critical = 1 + stats.crit * (stats.critDamage - 1);
    const hit = trait.multiHit ?? (!boss ? (trait.area ?? 1) : 1);
    return stats.atk * stats.speed * critical * hit * (boss ? (trait.bossDamage ?? 1) : 1);
  };
  return dps(false) * 0.65 + dps(true) * 0.35;
}

const effectiveHpFor = (archetypeKey, profile) => {
  const stats = statsFor(archetypeKey, profile);
  return stats.hp + stats.def * 12;
};

// 제한시간 안에 죽이는 판이 대부분이라 피해량 비중을 크게 둔다.
// scripts/tune-card-profiles.mjs 의 DAMAGE_WEIGHT 와 같은 값이어야 한다.
const DAMAGE_WEIGHT = 0.85;
const valueFor = (archetypeKey, profile) => (
  damageFor(archetypeKey, profile) ** DAMAGE_WEIGHT
  * effectiveHpFor(archetypeKey, profile) ** (1 - DAMAGE_WEIGHT)
);

const baseline = CARD_PROFILES[0];
let worstValue = 0;
let worstDamage = 0;
for (const profile of CARD_PROFILES) {
  for (const archetypeKey of archetypeKeys) {
    const value = Math.abs(valueFor(archetypeKey, profile) / valueFor(archetypeKey, baseline) - 1);
    const damage = Math.abs(damageFor(archetypeKey, profile) / damageFor(archetypeKey, baseline) - 1);
    assert.ok(value < 0.02, `${profile.label} x ${ARCHETYPES[archetypeKey].label} 종합 편차 ${(value * 100).toFixed(2)}% 가 2% 를 넘는다`);
    worstValue = Math.max(worstValue, value);
    worstDamage = Math.max(worstDamage, damage);
  }
}
// 피해량 자체도 크게 갈리면 안 된다. 체력은 시간제한 판에서 값을 못 하기 때문이다.
assert.ok(worstDamage < 0.035, `피해량 편차 ${(worstDamage * 100).toFixed(2)}% 가 3.5% 를 넘는다`);

// --- 개성: 그래도 스탯은 눈에 띄게 달라야 한다 ---
// 모두 1.0 에 수렴하면 프로필을 넣은 의미가 없다.
const spread = (field) => {
  const values = CARD_PROFILES.map((profile) => statsFor('combo', profile)[field]);
  return Math.max(...values) / Math.min(...values) - 1;
};
for (const field of ['atk', 'hp', 'speed']) {
  assert.ok(spread(field) > 0.03, `${field} 격차가 3% 미만이면 프로필이 보이지 않는다`);
}
const crits = CARD_PROFILES.map((profile) => statsFor('combo', profile).crit);
assert.ok(Math.max(...crits) - Math.min(...crits) >= 0.03, '치명타 확률 차이가 없다');
const critDamages = CARD_PROFILES.map((profile) => statsFor('combo', profile).critDamage);
assert.ok(Math.max(...critDamages) - Math.min(...critDamages) >= 0.1, '치명타 피해 차이가 없다');

// --- battle.js 와 tune 스크립트가 같은 계산을 해야 한다 ---
// 두 계산이 어긋나면 scale 이 잘못 잡히고도 조용히 지나간다.
for (const archetypeKey of archetypeKeys) {
  for (const profile of CARD_PROFILES) {
    const probe = combatCards.find((card) => cardProfileOf(card).key === profile.key);
    if (!probe) continue;
    const actual = computeCardStats({ ...probe, rarity: 'S', archetype: archetypeKey, enhancement: 5 });
    assert.deepEqual(actual, statsFor(archetypeKey, profile), `${profile.key} x ${archetypeKey} 계산이 어긋난다`);
  }
}

// --- 배정 ---
// 같은 카드는 항상 같은 프로필이어야 한다. 흔들리면 스냅샷 검증이 깨진다.
for (const card of combatCards.slice(0, 20)) {
  assert.equal(cardProfileOf(card).key, cardProfileOf({ ...card }).key);
}
// 한 프로필로 쏠리면 개성이 사라진다.
const counts = CARD_PROFILES.map((profile) => combatCards.filter((card) => cardProfileOf(card).key === profile.key).length);
assert.ok(Math.min(...counts) > 0, '한 장도 안 걸리는 프로필이 있다');
assert.ok(Math.max(...counts) / Math.min(...counts) < 2, '프로필 배정이 한쪽으로 쏠렸다');

// --- 카드 상세 표기 ---
// 표시하지 않으면 플레이어는 같은 등급·특성 카드의 스탯이 왜 다른지 알 수 없다.
const appSource = await readFile(new URL('../src/renewal/app.js', import.meta.url), 'utf8');
assert.match(appSource, /CARD_PROFILE_DESCRIPTIONS\[profile\.key\]/, '카드 상세에 프로필 설명이 나와야 한다');
assert.match(appSource, /card-detail-profile/, '프로필 표기 영역이 있어야 한다');

// --- 서버 공유 ---
// 클라이언트만 프로필을 알면 서버 재현 검증이 어긋나 명령이 거절된다.
const edgeConfig = await readFile(new URL('../supabase/functions/_shared/generated/config.js', import.meta.url), 'utf8');
assert.match(edgeConfig, /export const CARD_PROFILES/, 'Edge 공유 설정에 프로필이 없다');
for (const profile of CARD_PROFILES) {
  assert.ok(edgeConfig.includes(`key: '${profile.key}'`), `Edge 설정에 ${profile.key} 가 없다`);
  assert.ok(edgeConfig.includes(`scale: ${profile.scale}`), `Edge 설정의 ${profile.key} scale 이 어긋난다`);
}

console.log(
  `card profile tests passed: ${CARD_PROFILES.length} profiles, `
  + `종합 편차 ${(worstValue * 100).toFixed(2)}%, 피해량 편차 ${(worstDamage * 100).toFixed(2)}%`,
);
