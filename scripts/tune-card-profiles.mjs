// 카드 개성 프로필의 scale 보정값을 다시 계산한다.
//
// 프로필은 스탯 배분만 바꾸고 총 전투력은 건드리지 않는 것이 원칙이다. 배분을 바꾸면
// 전투력이 따라 움직이므로, 그만큼을 되돌리는 값이 scale 이다. 손으로 맞추면 특성마다
// 어긋나므로 여기서 8종 특성 전체에 대해 오차가 가장 작아지는 값을 찾는다.
//
//   node scripts/tune-card-profiles.mjs          결과만 출력
//   node scripts/tune-card-profiles.mjs --write  config.js 의 scale 을 갱신
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { ARCHETYPES, CARD_PROFILES, ENHANCEMENT, GAME_RULES, RARITIES } from '../src/renewal/config.js';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const configPath = path.join(root, 'src', 'renewal', 'config.js');

// battle.js 의 계산을 그대로 옮긴다. scale 을 인자로 넣어 시험해야 하므로 재구현한다.
// 여기가 battle.js 와 어긋나면 tune 결과가 틀리므로 tests/renewal-card-profiles.test.js 가
// 두 계산이 같은 값을 내는지 검증한다.
function statsOf(archetypeKey, profile, scale, rarity = 'S', enhancement = 5) {
  const base = GAME_RULES.baseCardStats;
  const archetype = ARCHETYPES[archetypeKey];
  const common = RARITIES[rarity].multiplier * ENHANCEMENT.statMultipliers[enhancement] * scale;
  return {
    atk: Math.round(base.atk * common * (archetype.atk ?? 1) * profile.atk),
    hp: Math.round(base.hp * common * (archetype.hp ?? 1) * profile.hp),
    def: Math.round(base.def * common * (archetype.def ?? 1) * profile.def),
    speed: Number((base.speed * (archetype.speed ?? 1) * profile.speed).toFixed(2)),
    crit: Number(Math.min(0.6, base.crit + (archetype.crit ?? 0) + profile.crit).toFixed(3)),
    critDamage: Number((base.critDamage + (archetype.critDamage ?? 0) + profile.critDamage).toFixed(2)),
  };
}

// 기준은 표시 전투력이 아니라 실제 피해량이다.
// 표시 전투력은 체력을 0.2, 방어를 2.4 로 쳐주는데, 제한시간 안에 죽여야 하는 판에서는
// 죽지만 않으면 체력이 한 푼도 값을 못 한다. 표시 전투력만 맞추면 체력형 프로필이
// 숫자상 동급이면서 실전에서 10% 약한 함정 카드가 된다.
function damageOf(archetypeKey, profile, scale) {
  const stats = statsOf(archetypeKey, profile, scale);
  const trait = ARCHETYPES[archetypeKey];
  const dps = (boss) => {
    const critical = 1 + stats.crit * (stats.critDamage - 1);
    const hit = trait.multiHit ?? (!boss ? (trait.area ?? 1) : 1);
    return stats.atk * stats.speed * critical * hit * (boss ? (trait.bossDamage ?? 1) : 1);
  };
  return dps(false) * 0.65 + dps(true) * 0.35;
}

// 참고용. 체력형이 딜을 깎아 먹은 만큼 실제로 단단해졌는지 보기 위한 값이다.
function effectiveHpOf(archetypeKey, profile, scale) {
  const stats = statsOf(archetypeKey, profile, scale);
  return stats.hp + stats.def * 12;
}

const archetypeKeys = Object.keys(ARCHETYPES);
const baseline = CARD_PROFILES[0];
if (baseline.key !== 'balanced' || baseline.scale !== 1) {
  throw new Error('첫 프로필은 보정 없는 기준(balanced, scale 1)이어야 한다');
}
// 피해량만 기준으로 맞추면 체력이 공짜가 된다. 체력형은 딜 손실 없이 더 단단해지고,
// 공격형은 아무 대가 없이 물러진다 — 그러면 다시 우열이 생긴다.
// 피해량과 유효 체력을 함께 본다. 대부분의 판이 제한시간 안에 죽이는 싸움이라
// 피해량에 훨씬 큰 비중을 준다.
const DAMAGE_WEIGHT = 0.85;
const valueOf = (key, profile, scale) => (
  damageOf(key, profile, scale) ** DAMAGE_WEIGHT
  * effectiveHpOf(key, profile, scale) ** (1 - DAMAGE_WEIGHT)
);

const targets = archetypeKeys.map((key) => damageOf(key, baseline, 1));
const hpTargets = archetypeKeys.map((key) => effectiveHpOf(key, baseline, 1));
const valueTargets = archetypeKeys.map((key) => valueOf(key, baseline, 1));

// scale 을 이분 탐색한다. 값은 scale 에 대해 단조 증가라 안전하다.
function solveScale(profile) {
  const error = (scale) => archetypeKeys.reduce((sum, key, index) => (
    sum + (valueOf(key, profile, scale) / valueTargets[index] - 1)
  ), 0);
  let low = 0.5;
  let high = 1.5;
  for (let step = 0; step < 60; step += 1) {
    const mid = (low + high) / 2;
    if (error(mid) > 0) high = mid; else low = mid;
  }
  return Number(((low + high) / 2).toFixed(4));
}

const results = CARD_PROFILES.map((profile) => {
  const scale = profile.key === baseline.key ? 1 : solveScale(profile);
  const dmg = archetypeKeys.map((key, index) => damageOf(key, profile, scale) / targets[index] - 1);
  const hp = archetypeKeys.map((key, index) => effectiveHpOf(key, profile, scale) / hpTargets[index] - 1);
  const value = archetypeKeys.map((key, index) => valueOf(key, profile, scale) / valueTargets[index] - 1);
  return {
    profile,
    scale,
    worstValue: Math.max(...value.map(Math.abs)),
    meanDamage: dmg.reduce((sum, entry) => sum + entry, 0) / dmg.length,
    meanHp: hp.reduce((sum, entry) => sum + entry, 0) / hp.length,
    perArchetype: archetypeKeys.map((key, index) => [ARCHETYPES[key].label, value[index]]),
  };
});

const signed = (value) => `${value >= 0 ? '+' : ''}${(value * 100).toFixed(1)}%`;
console.log('프로필   scale     피해량   유효체력   종합편차');
for (const row of results) {
  console.log(
    row.profile.label.padEnd(5),
    row.scale.toFixed(4).padStart(7),
    signed(row.meanDamage).padStart(8),
    signed(row.meanHp).padStart(9),
    `${(row.worstValue * 100).toFixed(2)}%`.padStart(9),
  );
}
const dmgs = results.map((row) => row.meanDamage);
const hps = results.map((row) => row.meanHp);
console.log(`
종합 최대 편차: ${(Math.max(...results.map((row) => row.worstValue)) * 100).toFixed(2)}%`);
console.log(`피해량 폭: ${((Math.max(...dmgs) - Math.min(...dmgs)) * 100).toFixed(1)}%p`);
console.log(`유효 체력 폭: ${((Math.max(...hps) - Math.min(...hps)) * 100).toFixed(1)}%p`);

if (process.argv.includes('--write')) {
  let source = readFileSync(configPath, 'utf8');
  for (const row of results) {
    const pattern = new RegExp(`(\\{ key: '${row.profile.key}',[^}]*scale: )[0-9.]+`);
    if (!pattern.test(source)) throw new Error(`${row.profile.key} 프로필을 config.js 에서 못 찾았다`);
    source = source.replace(pattern, `$1${row.scale}`);
  }
  writeFileSync(configPath, source);
  console.log('config.js 의 scale 을 갱신했다.');
}
