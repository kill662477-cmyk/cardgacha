import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { ARCHETYPES, PACKS, STAGES } from '../src/renewal/config.js';
import { computeCardPower, computeCardStats, computeFormationPower, getFormationCritAura, getRaceSynergy, simulateBattle } from '../src/renewal/battle.js';

const cards = JSON.parse(await fs.readFile(new URL('../data/renewal-demo-cards.json', import.meta.url), 'utf8'));
const formation = cards.slice(0, 5);

assert.equal(cards.length, 20, 'demo card pool must contain 20 cards');
assert.equal(new Set(cards.map((card) => card.id)).size, 20, 'demo card ids must be unique');
assert.equal(STAGES.length, 100, 'normal and hard adventure must contain 100 stages');

Object.entries(PACKS).forEach(([packId, pack]) => {
  const total = Object.values(pack.rates).reduce((sum, rate) => sum + rate, 0);
  assert.ok(Math.abs(total - 100) < 0.00001, `${packId} rates must sum to 100`);
});

cards.forEach((card) => {
  const stats = computeCardStats(card);
  assert.ok(stats && stats.atk > 0 && stats.hp > 0 && stats.def > 0, `${card.id} must have valid battle stats`);
});

assert.ok(computeFormationPower(formation) > 0, 'formation power must be positive');
const first = simulateBattle(formation, STAGES[0]);
const second = simulateBattle(formation, STAGES[0]);
assert.deepEqual(first, second, 'same formation and stage must produce deterministic results');
assert.ok(first.events.length > 0, 'battle must produce playback events');
assert.equal(first.victory, true, 'default formation should clear stage 1');

const raceDeck = (sameRaceCount) => cards.slice(0, 5).map((card, index) => ({
  ...card,
  race: index < sameRaceCount ? 'Z' : index === 4 ? 'P' : 'T',
}));
assert.equal(getRaceSynergy(raceDeck(3)).atk, 1.05);
assert.equal(getRaceSynergy(raceDeck(4)).atk, 1.05, 'four matching cards must retain the three-card synergy');
assert.equal(getRaceSynergy(raceDeck(5)).atk, 1.12);

const roleCard = (archetype) => ({ id: `role-${archetype}`, rarity: 'SSS', enhancement: 0, archetype, race: 'Z' });
assert.ok(computeCardPower(roleCard('combo')) > computeCardPower(roleCard('sustain')), 'displayed power must reflect combat throughput instead of raw HP alone');
// 증폭은 편성 전체 치명타 오라다. 8종 중 유일하게 중첩된다.
assert.equal(getFormationCritAura([roleCard('amplify'), roleCard('quick')]), 0.15);
assert.equal(getFormationCritAura([roleCard('amplify'), roleCard('amplify')]), 0.3);
assert.equal(getFormationCritAura([roleCard('quick'), roleCard('combo')]), 0);
// 오라는 자신뿐 아니라 다른 카드의 치명타 확률도 올려야 한다.
assert.ok(
  computeCardStats(roleCard('combo'), { crit: 0.15 }).crit > computeCardStats(roleCard('combo')).crit,
  '증폭 오라가 다른 특성 카드에도 적용돼야 한다',
);
// 상한이 없으면 증폭 5장에서 치명타가 과하게 올라 딜 편차가 사라진다.
assert.equal(computeCardStats(roleCard('combo'), { crit: 5 }).crit, 0.6);

for (const archetype of ['quick', 'heavy', 'combo', 'area', 'boss', 'amplify', 'weaken', 'sustain']) {
  const sssPlusThree = computeCardPower({ id: `tier-check-${archetype}`, rarity: 'SSS', enhancement: 3, archetype, race: 'Z' });
  const sPlusNine = computeCardPower({ id: `tier-check-${archetype}`, rarity: 'S', enhancement: 9, archetype, race: 'Z' });
  assert.ok(sssPlusThree > sPlusNine, `SSS +3 ${archetype} must exceed S +9 at equal conditions`);
}

const areaDeck = Array.from({ length: 5 }, (_, index) => ({ ...roleCard('area'), id: `area-${index}` }));
const target = { id: 'area-target', enemyHp: 999_999_999, enemyAttack: 0, duration: 10 };
const areaNormal = simulateBattle(areaDeck, { ...target, boss: false });
const areaBoss = simulateBattle(areaDeck, { ...target, boss: true });
const totalDamage = (result) => result.damageByCard.reduce((sum, entry) => sum + entry.damage, 0);
assert.ok(totalDamage(areaNormal) > totalDamage(areaBoss), 'area bonus must apply to normal waves only');

console.log(`renewal battle tests passed: ${cards.length} cards, ${STAGES.length} stages, ${first.events.length} events`);

// 약화 감소폭은 하드코딩이 아니라 ARCHETYPES.weaken.weaken 을 따라야 한다.
// 하드코딩으로 되돌아가면 설정을 바꿔도 전투가 안 변한다(실제로 0.08 설정과 0.92 하드코딩이
// 따로 놀아, 설정값은 전투력 점수에만 쓰이고 전투에는 반영되지 않았다).
const battleSource = await fs.readFile(new URL('../src/renewal/battle.js', import.meta.url), 'utf8');
assert.match(battleSource, /1 - weakenAmount/, '약화 감소폭은 특성 설정값에서 와야 한다');
assert.doesNotMatch(battleSource, /weakenedUntil \? 0\.92/, '하드코딩된 0.92 가 남아 있으면 안 된다');
assert.equal(ARCHETYPES.weaken.weaken, 0.15);
assert.equal(ARCHETYPES.weaken.weakenDamage, 0.1);
// 적 방어력 스탯이 없어 '방어력 감소'는 적이 받는 피해 증가로 구현했다.
assert.match(battleSource, /1 \+ weakenDamageAmount/, '약화는 적이 받는 피해도 늘려야 한다');
assert.match(
  battleSource,
  /weakenDamageAmount = Math\.max\(weakenDamageAmount, trait\.weakenDamage \?\? 0\)/,
  '피해 증가분도 누적되면 안 된다',
);

// 약화는 중첩되지 않는다. 여러 장을 넣어도 적 공격력 감소폭은 동일해야 한다.
const weakStage = STAGES.find((s) => s.id === '3-5');
const wCard = (i, n) => ({ id: `w-${i}`, rarity: 'SS', enhancement: 7, archetype: i < n ? 'weaken' : 'combo', race: '저그' });
const incomingWith = (n) => {
  const f = Array.from({ length: 5 }, (_, i) => wCard(i, n));
  const r = simulateBattle(f, weakStage, {}, 7);
  const hits = r.events.filter((e) => e.type === 'enemy');
  return hits.length ? Math.min(...hits.map((e) => e.damage)) : 0;
};
assert.ok(incomingWith(1) < incomingWith(0), '약화 1장은 받는 피해를 줄여야 한다');
// 중첩 여부는 실측으로 분리할 수 없다. 약화 카드는 방어력도 1.02 라, 여러 장 넣으면
// 디버프와 무관하게 평균 방어가 올라 피해가 줄어든다. 그래서 누적되지 않는다는 것은
// 코드 구조로 잠근다(더하기·곱하기가 아니라 최대값 하나만 취해야 한다).
assert.match(
  battleSource,
  /weakenAmount = Math\.max\(weakenAmount, trait\.weaken\)/,
  '약화는 장수만큼 누적되면 안 된다. 가장 강한 값 하나만 적용해야 한다',
);

console.log('weaken archetype tests passed: config-driven 15%, no stacking');
