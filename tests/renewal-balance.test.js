import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { STAGES } from '../src/renewal/config.js';
import { computeCardPower, simulateBattle } from '../src/renewal/battle.js';
import { applyGuildBuff, calculateCollectionBonuses } from '../src/renewal/collection.js';

const cards = JSON.parse(await fs.readFile(new URL('../data/renewal-demo-cards.json', import.meta.url), 'utf8'));
const allCards = JSON.parse(await fs.readFile(new URL('../data/renewal-cards.json', import.meta.url), 'utf8'));
const topDeck = cards.slice(0, 5).map((card) => ({ ...card, enhancement: 0 }));
const midDeck = cards.slice(5, 10).map((card) => ({ ...card, enhancement: 0 }));
const lowDeck = cards.slice(15, 20).map((card) => ({ ...card, enhancement: 0 }));
const maxedTopDeck = topDeck.map((card) => ({ ...card, enhancement: 9 }));
const maxedLowDeck = lowDeck.map((card) => ({ ...card, enhancement: 9 }));
const fullCollection = calculateCollectionBonuses(allCards, Object.fromEntries(allCards.map((card) => [card.id, true])));

// 저성능 무강 덱은 지역 1 안에서 막혀야 한다. 광역 상향으로 벽이 1-6에서
// 1-7로 한 칸 이동했지만 초기 성장 벽은 유지된다.
assert.equal(simulateBattle(lowDeck, STAGES[5]).victory, true, 'unmaxed low deck should clear 1-6');
assert.equal(simulateBattle(lowDeck, STAGES[6]).victory, false, 'unmaxed low deck should stop at 1-7');
assert.equal(simulateBattle(midDeck, STAGES[9]).victory, true, 'mid deck should clear the first region');
assert.equal(simulateBattle(topDeck, STAGES[9]).victory, true, 'top deck should clear the first region');
assert.equal(simulateBattle(topDeck, STAGES[10]).victory, true, 'top deck may enter region 2');
STAGES.slice(0, 10).forEach((stage) => {
  assert.equal(simulateBattle(maxedLowDeck, stage).victory, true, `maxed low-rarity deck should clear ${stage.id}`);
});

for (let region = 0; region < 5; region += 1) {
  const stages = STAGES.slice(region * 10, region * 10 + 10);
  for (let index = 1; index < stages.length; index += 1) {
    if (!stages[index].boss) {
      assert.ok(stages[index].enemyHp / stages[index].duration > stages[index - 1].enemyHp / stages[index - 1].duration, `${stages[index].id} damage requirement must increase`);
    }
    const interval = stages[index].boss ? 1.15 : 1.45;
    const previousInterval = stages[index - 1].boss ? 1.15 : 1.45;
    assert.ok(stages[index].enemyAttack / interval > stages[index - 1].enemyAttack / previousInterval, `${stages[index].id} incoming pressure must increase`);
  }
}

assert.equal(simulateBattle(maxedTopDeck, STAGES[49], fullCollection).victory, true, 'maxed deck with full collection should clear the final boss');

// nolevel-1: S 9성(고강)과 SS 5~6성(중강) 덱은 계정 레벨 없이 완주 가능.
// 도감 보너스 없이도 완주해야 한다. D/E/F 9성 덱은 최종 보스에서 막힌다.
function rarityDeck(rarity, enhancement) {
  return allCards
    .filter((card) => card.rarity === rarity && card.archetype)
    .map((card) => ({ ...card, enhancement }))
    .sort((left, right) => computeCardPower(right) - computeCardPower(left))
    .slice(0, 5);
}
const cardOnlyBonuses = { attack: 0, hp: 0, defense: 0, bossDamage: 0, idle: 0 };
const normalStages = STAGES.filter((stage) => stage.mode === 'normal');
const clearsAll = (deck, bonuses) => normalStages.every((stage) => simulateBattle(deck, stage, bonuses).victory);
const stallsBeforeEnd = (deck, bonuses) => !simulateBattle(deck, STAGES[49], bonuses).victory;
const reaches = (deck, bonuses = cardOnlyBonuses) => {
  let cleared = 0;
  for (const stage of normalStages) {
    if (!simulateBattle(deck, stage, bonuses).victory) break;
    cleared = stage.globalNumber;
  }
  return cleared;
};

const fixedArchetypes = ['quick', 'heavy', 'combo', 'boss', 'sustain'];
const isolatedRarityDeck = (rarity, enhancement = 0) => fixedArchetypes.map((archetype, index) => ({
  id: `rarity-balance-${index}`,
  member: `등급검증${index}`,
  rarity,
  enhancement,
  archetype,
  race: 'Z',
}));
const zeroStarReach = ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'].map((rarity) => reaches(isolatedRarityDeck(rarity)));
// 검증 덱 5장 중 2장(강타·생존)이 상향 대상이라 저·중등급 도달 구간이 2~3 스테이지 늘었다.
// 고등급 종착점(SS 30 / SSS 40)은 그대로라 엔드게임 벽은 유지된다.
assert.deepEqual(zeroStarReach, [4, 6, 8, 10, 12, 20, 20, 30, 40], 'zero-star rarity progression must reflect the SS/SSS rarity retune and the heavy/sustain buff');

const combatRarities = ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'];
for (let rarityIndex = 1; rarityIndex < combatRarities.length; rarityIndex += 1) {
  for (const archetype of ['quick', 'heavy', 'combo', 'area', 'boss', 'amplify', 'weaken', 'sustain']) {
    const lower = allCards
      .filter((card) => card.rarity === combatRarities[rarityIndex - 1] && card.archetype === archetype)
      .map((card) => computeCardPower({ ...card, enhancement: 0 }));
    const higher = allCards
      .filter((card) => card.rarity === combatRarities[rarityIndex] && card.archetype === archetype)
      .map((card) => computeCardPower({ ...card, enhancement: 0 }));
    assert.ok(Math.min(...higher) > Math.max(...lower), `${combatRarities[rarityIndex]} ${archetype} must outrank the lower rarity at equal enhancement`);
  }
}

assert.equal(clearsAll(rarityDeck('SS', 9), fullCollection), true, 'SS 9성 deck with full collection must full-clear');
assert.equal(clearsAll(rarityDeck('S', 9), fullCollection), true, 'S 9성 deck with full collection can now full-clear after 5-10 nerf');
assert.equal(stallsBeforeEnd(isolatedRarityDeck('F', 9), cardOnlyBonuses), true, 'F 9성 deck must retain an endgame wall');
assert.equal(stallsBeforeEnd(isolatedRarityDeck('E', 9), cardOnlyBonuses), true, 'E 9성 deck must retain an endgame wall');
assert.equal(stallsBeforeEnd(isolatedRarityDeck('D', 9), cardOnlyBonuses), true, 'D 9성 deck must retain an endgame wall');
const lowRegion5Deck = [...rarityDeck('D', 9).slice(0, 2), ...rarityDeck('E', 9).slice(0, 2), ...rarityDeck('F', 9).slice(0, 1)];
assert.equal(stallsBeforeEnd(lowRegion5Deck, cardOnlyBonuses), true, 'low-rarity D/E/F 9성 deck must NOT full-clear (endgame wall)');

// 최종 HELL: SSS 9강 + 올도감 + 길드 Lv.10의 역할 편성만 완주한다.
// 같은 편성의 8강 또는 길드 버프 누락은 적어도 한 스테이지에서 막혀야 한다.
const hellStages = STAGES.filter((stage) => stage.mode === 'hell');
const hellTargetIds = ['jidudu-1', 'tomato-11', 'haetsal-12', 'kimmincheol-7', 'jidongwon-8'];
const hellDeck = hellTargetIds.map((id) => ({ ...allCards.find((card) => card.id === id), enhancement: 9 }));
const guildLevel10Bonuses = applyGuildBuff(fullCollection, { level: 10, atk: 0.05, hp: 0.05, def: 0.04 });
const guildOnlyBonuses = applyGuildBuff(cardOnlyBonuses, { level: 10, atk: 0.05, hp: 0.05, def: 0.04 });
assert.equal(hellStages.length, 10);
assert.equal(hellStages.at(-1).enemyHp, 48_000_000);
assert.equal(hellStages.at(-1).enemyAttack, 50_000);
assert.equal(hellStages.every((stage) => simulateBattle(hellDeck, stage, guildLevel10Bonuses).victory), true);
assert.equal(
  hellStages.every((stage) => simulateBattle(hellDeck.map((card) => ({ ...card, enhancement: 8 })), stage, guildLevel10Bonuses).victory),
  false,
  'SSS 8성 편성은 HELL을 완주할 수 없어야 한다',
);
assert.equal(
  hellStages.every((stage) => simulateBattle(hellDeck, stage, fullCollection).victory),
  false,
  '길드 Lv.10 버프가 없는 편성은 HELL을 완주할 수 없어야 한다',
);
const hellFinalResult = simulateBattle(hellDeck, hellStages.at(-1), guildLevel10Bonuses);
assert.ok(hellFinalResult.duration >= hellStages.at(-1).duration * 0.9, 'Hell10은 제한시간 끝자락에서 클리어되어야 한다');

// 고정 기준 덱만 검사하면 새 카드/특성 상향 뒤 다른 조합이 난이도 조건을 우회할 수 있다.
// 현재 SSS 21장의 모든 5장 조합을 검사해 길드·도감·9강 조건과 최단 클리어 시간을 함께 잠근다.
const hellSssCards = allCards
  .filter((card) => card.rarity === 'SSS' && card.archetype)
  .map((card) => ({ ...card, enhancement: 9 }));
const hellDeckCandidates = [];
for (let first = 0; first < hellSssCards.length - 4; first += 1) {
  for (let second = first + 1; second < hellSssCards.length - 3; second += 1) {
    for (let third = second + 1; third < hellSssCards.length - 2; third += 1) {
      for (let fourth = third + 1; fourth < hellSssCards.length - 1; fourth += 1) {
        for (let fifth = fourth + 1; fifth < hellSssCards.length; fifth += 1) {
          hellDeckCandidates.push([
            hellSssCards[first],
            hellSssCards[second],
            hellSssCards[third],
            hellSssCards[fourth],
            hellSssCards[fifth],
          ]);
        }
      }
    }
  }
}
const fullHellResult = (deck, bonuses) => {
  let finalResult = null;
  for (const stage of hellStages) {
    finalResult = simulateBattle(deck, stage, bonuses);
    if (!finalResult.victory) return null;
  }
  return finalResult;
};
const qualifiedHellResults = hellDeckCandidates
  .map((deck) => fullHellResult(deck, guildLevel10Bonuses))
  .filter(Boolean);
assert.ok(qualifiedHellResults.length > 0, '올 SSS 9강·올도감·길드 Lv.10 조합은 HELL 완주가 가능해야 한다');
assert.ok(
  Math.min(...qualifiedHellResults.map(({ duration }) => duration)) >= hellStages.at(-1).duration * 0.9,
  '어떤 SSS 9강 조합도 Hell10을 제한시간 90% 전에 끝내면 안 된다',
);
assert.equal(
  hellDeckCandidates.some((deck) => fullHellResult(deck, fullCollection)),
  false,
  '길드 Lv.10 없이 완주 가능한 SSS 9강 조합이 있으면 안 된다',
);
assert.equal(
  hellDeckCandidates.some((deck) => fullHellResult(
    deck.map((card) => ({ ...card, enhancement: 8 })),
    guildLevel10Bonuses,
  )),
  false,
  'SSS 8강으로 완주 가능한 조합이 있으면 안 된다',
);
assert.equal(
  hellDeckCandidates.some((deck) => fullHellResult(deck, guildOnlyBonuses)),
  false,
  '도감 100% 없이 완주 가능한 조합이 있으면 안 된다',
);

console.log('renewal balance tests passed: monotonic stages, low-rarity region 1, S9/SS5-6 full-clear, low-deck endgame wall');
