import { COLLECTION_RULES, RARITY_ORDER, RARITIES } from './config.js';

const MEMBER_STATS = ['attack', 'hp', 'defense'];
const RACE_STATS = { 저그: 'attack', 테란: 'defense', 프로토스: 'hp' };

export const COLLECTION_MEMBER_ORDER = Object.freeze([
  '김윤환', '소주양', '지두두', '남덕선', '토마토', '햇살', '찌킹', '치리',
  '주하랑', '임조이', '비타밍', '먼진', '아리송이', '낭니', '변현제', '김민철',
  '사테', '박준오', '박수범', '지동원', '배성흠',
]);

function completedGroup(type, key, groupCards, records, reward) {
  const registered = groupCards.filter((card) => records[card.id]).length;
  return {
    type,
    key,
    label: key,
    registered,
    total: groupCards.length,
    complete: groupCards.length > 0 && registered === groupCards.length,
    reward,
  };
}

function groupCards(cards, keySelector) {
  return cards.reduce((groups, card) => {
    const key = keySelector(card);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(card);
    return groups;
  }, new Map());
}

function stableMemberStat(member) {
  const sum = [...member].reduce((total, character) => total + character.codePointAt(0), 0);
  return MEMBER_STATS[sum % MEMBER_STATS.length];
}

function addBonus(target, stat, amount) {
  target[stat] = (target[stat] ?? 0) + amount;
}

export function groupCollectionCardsByMember(cards, memberOrder = COLLECTION_MEMBER_ORDER) {
  const groups = groupCards(cards, (card) => card.member);
  const order = new Map(memberOrder.map((member, index) => [member, index]));
  const firstSeen = new Map([...groups.keys()].map((member, index) => [member, index]));
  const rarityRank = (rarity) => rarity === 'EX' ? RARITY_ORDER.length : RARITY_ORDER.indexOf(rarity);
  return [...groups.entries()]
    .sort(([left], [right]) => {
      const leftRank = order.get(left) ?? memberOrder.length + firstSeen.get(left);
      const rightRank = order.get(right) ?? memberOrder.length + firstSeen.get(right);
      return leftRank - rightRank;
    })
    .map(([member, memberCards]) => ({
      member,
      cards: memberCards
        .map((card, index) => ({ card, index }))
        .sort((left, right) => rarityRank(right.card.rarity) - rarityRank(left.card.rarity) || left.index - right.index)
        .map(({ card }) => card),
    }));
}

export function buildCollectionModel(cards, records = {}) {
  const battleCards = cards.filter((card) => !RARITIES[card.rarity]?.displayOnly);
  const exCards = cards.filter((card) => RARITIES[card.rarity]?.displayOnly);
  const registered = battleCards.filter((card) => records[card.id]).length;
  const ratio = battleCards.length > 0 ? registered / battleCards.length : 0;

  const members = [...groupCards(battleCards, (card) => card.member).entries()]
    .sort(([left], [right]) => left.localeCompare(right, 'ko'))
    .map(([member, group]) => completedGroup('member', member, group, records, {
      stat: stableMemberStat(member), amount: COLLECTION_RULES.memberCompletionBonus,
    }));
  const races = [...groupCards(battleCards, (card) => card.race).entries()]
    .sort(([left], [right]) => left.localeCompare(right, 'ko'))
    .map(([race, group]) => completedGroup('race', race, group, records, {
      stat: RACE_STATS[race] ?? 'attack', amount: COLLECTION_RULES.raceCompletionBonus,
    }));
  const rarities = RARITY_ORDER
    .filter((rarity) => battleCards.some((card) => card.rarity === rarity))
    .map((rarity) => completedGroup('rarity', rarity, battleCards.filter((card) => card.rarity === rarity), records, {
      stat: 'bossDamage', amount: COLLECTION_RULES.rarityCompletionBonus,
    }));
  const overall = COLLECTION_RULES.overallMilestones.map((threshold, index) => ({
    type: 'overall',
    key: String(threshold),
    label: `전체 ${Math.round(threshold * 100)}%`,
    registered,
    total: battleCards.length,
    complete: ratio >= threshold,
    reward: {
      stat: ['attack', 'hp', 'defense', 'bossDamage'][index % 4],
      amount: COLLECTION_RULES.overallCompletionBonus,
    },
  }));
  return {
    registered,
    total: battleCards.length,
    ratio,
    exRegistered: exCards.filter((card) => records[card.id]).length,
    exTotal: exCards.length,
    groups: { members, races, rarities, overall },
  };
}

export function calculateCollectionBonuses(cards, records = {}) {
  const model = buildCollectionModel(cards, records);
  const bonuses = { attack: 0, hp: 0, defense: 0, bossDamage: 0, idle: 0 };
  [...model.groups.members, ...model.groups.races, ...model.groups.rarities, ...model.groups.overall]
    .filter((group) => group.complete)
    .forEach((group) => addBonus(bonuses, group.reward.stat, group.reward.amount));
  bonuses.idle = model.groups.overall.filter((group) => group.complete).length * COLLECTION_RULES.idlePerMilestone
    + model.groups.races.filter((group) => group.complete).length * COLLECTION_RULES.idlePerRaceCompletion;

  const combatTotal = bonuses.attack + bonuses.hp + bonuses.defense + bonuses.bossDamage;
  const capped = combatTotal > COLLECTION_RULES.combatBonusCap;
  if (capped) {
    const scale = COLLECTION_RULES.combatBonusCap / combatTotal;
    ['attack', 'hp', 'defense', 'bossDamage'].forEach((stat) => { bonuses[stat] *= scale; });
  }
  Object.keys(bonuses).forEach((stat) => { bonuses[stat] = Number(bonuses[stat].toFixed(6)); });
  let finalCombatTotal = Number((bonuses.attack + bonuses.hp + bonuses.defense + bonuses.bossDamage).toFixed(6));
  if (capped && finalCombatTotal !== COLLECTION_RULES.combatBonusCap) {
    bonuses.attack = Number((bonuses.attack + COLLECTION_RULES.combatBonusCap - finalCombatTotal).toFixed(6));
    finalCombatTotal = COLLECTION_RULES.combatBonusCap;
  }
  return { ...bonuses, combatTotal: finalCombatTotal, model };
}
