import { ARCHETYPES, ENHANCEMENT, GAME_RULES, RARITIES } from './config.js';

function hashString(value) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state += 0x6d2b79f5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function cardVariation(card) {
  return 0.97 + (hashString(card.id) % 13) / 200;
}

export function computeCardStats(card, accountBonuses = {}) {
  const rarity = RARITIES[card.rarity];
  const archetype = ARCHETYPES[card.archetype];
  if (!rarity || rarity.displayOnly || !archetype) return null;

  // nolevel-1: accountLevelMultiplier 제거. 카드 자체(등급 × 강화 × 변동치)만으로 스케일링.
  const base = GAME_RULES.baseCardStats;
  const enhance = ENHANCEMENT.statMultipliers[card.enhancement] ?? 1;
  const common = rarity.multiplier * enhance * cardVariation(card);
  return {
    atk: Math.round(base.atk * common * (archetype.atk ?? 1) * (1 + (accountBonuses.attack ?? 0))),
    hp: Math.round(base.hp * common * (archetype.hp ?? 1) * (1 + (accountBonuses.hp ?? 0))),
    def: Math.round(base.def * common * (archetype.def ?? 1) * (1 + (accountBonuses.defense ?? 0))),
    speed: Number((base.speed * (archetype.speed ?? 1)).toFixed(2)),
    crit: Number((base.crit + (archetype.crit ?? 0)).toFixed(3)),
    critDamage: Number((base.critDamage + (archetype.critDamage ?? 0)).toFixed(2)),
  };
}

function expectedDamagePerSecond(stats, trait, boss = false) {
  const criticalMultiplier = 1 + stats.crit * (stats.critDamage - 1);
  const hitMultiplier = trait.multiHit ?? (!boss ? (trait.area ?? 1) : 1);
  const bossMultiplier = boss ? (trait.bossDamage ?? 1) : 1;
  return stats.atk * stats.speed * criticalMultiplier * hitMultiplier * bossMultiplier;
}

export function computeCardPower(card, accountBonuses = {}) {
  const stats = computeCardStats(card, accountBonuses);
  if (!stats) return 0;
  const trait = ARCHETYPES[card.archetype];
  const generalDamage = expectedDamagePerSecond(stats, trait, false);
  const bossDamage = expectedDamagePerSecond(stats, trait, true);
  const weightedDamage = generalDamage * 0.65 + bossDamage * 0.35;
  const recoveryValue = stats.hp * (trait.recovery ?? 0) * stats.speed * 0.3;
  const weakenValue = (stats.hp * 0.2 + stats.def * 2.4) * (trait.weaken ?? 0);
  return Math.round(weightedDamage * 2.5 + stats.hp * 0.2 + stats.def * 2.4 + recoveryValue + weakenValue);
}

export function getRaceSynergy(formation) {
  const counts = formation.reduce((result, card) => {
    result[card.race] = (result[card.race] ?? 0) + 1;
    return result;
  }, {});
  const strongest = Object.entries(counts).sort((left, right) => right[1] - left[1])[0] ?? [null, 0];
  const threshold = strongest[1] >= 5 ? 5 : strongest[1] >= 3 ? 3 : 0;
  const bonus = GAME_RULES.raceSynergy[threshold] ?? { atk: 1, hp: 1 };
  return { race: strongest[0], count: strongest[1], ...bonus };
}

export function getFormationAmplifier(formation) {
  return 1 + formation.reduce((total, card) => total + (ARCHETYPES[card.archetype]?.amplify ?? 0), 0);
}

function combineBonus(baseBonus, multiplier) {
  return (1 + (baseBonus ?? 0)) * multiplier - 1;
}

export function computeFormationPower(formation, accountBonuses = {}) {
  const synergy = getRaceSynergy(formation);
  const amplify = getFormationAmplifier(formation);
  const formationBonuses = {
    ...accountBonuses,
    attack: combineBonus(accountBonuses.attack, synergy.atk * amplify),
    hp: combineBonus(accountBonuses.hp, synergy.hp),
  };
  return formation.reduce((total, card) => total + computeCardPower(card, formationBonuses), 0);
}

export function simulateBattle(formation, stage, accountBonuses = {}) {
  if (!Array.isArray(formation) || formation.length !== GAME_RULES.formationSize) {
    throw new Error(`Formation must contain ${GAME_RULES.formationSize} battle cards.`);
  }
  if (!stage) throw new Error('Stage configuration is required.');

  const seed = hashString(`${stage.id}:${formation.map((card) => card.id).join('|')}`);
  const random = seededRandom(seed);
  const synergy = getRaceSynergy(formation);
  const amplify = getFormationAmplifier(formation);
  const fighters = formation.map((card, index) => ({
    card,
    index,
    stats: computeCardStats(card, accountBonuses),
    nextAttack: index * 0.08,
    damage: 0,
  }));
  let enemyHp = stage.enemyHp;
  let partyHp = fighters.reduce((total, fighter) => total + fighter.stats.hp * synergy.hp, 0);
  const partyMaxHp = partyHp;
  const events = [];
  let elapsed = 0;
  let nextEnemyAttack = 1.4;
  let weakenedUntil = 0;

  while (elapsed <= stage.duration && enemyHp > 0 && partyHp > 0) {
    fighters.forEach((fighter) => {
      if (enemyHp <= 0 || elapsed + 0.0001 < fighter.nextAttack) return;
      const trait = ARCHETYPES[fighter.card.archetype];
      const critical = random() < fighter.stats.crit;
      const spread = 0.92 + random() * 0.16;
      const bossBonus = stage.boss ? (trait.bossDamage ?? 1) * (1 + (accountBonuses.bossDamage ?? 0)) : 1;
      const hitBonus = trait.multiHit ?? (!stage.boss ? (trait.area ?? 1) : 1);
      let damage = fighter.stats.atk * spread * synergy.atk * amplify * bossBonus * hitBonus;
      if (critical) damage *= fighter.stats.critDamage;
      damage = Math.max(1, Math.round(damage));
      enemyHp = Math.max(0, enemyHp - damage);
      fighter.damage += damage;
      if (trait.weaken) weakenedUntil = Math.max(weakenedUntil, elapsed + 2.5);
      if (trait.recovery) partyHp = Math.min(partyMaxHp, partyHp + fighter.stats.hp * trait.recovery);
      events.push({ type: 'attack', at: elapsed, cardIndex: fighter.index, damage, critical, enemyHp });
      fighter.nextAttack += 1 / fighter.stats.speed;
    });

    if (enemyHp > 0 && elapsed + 0.0001 >= nextEnemyAttack) {
      const averageDef = fighters.reduce((sum, fighter) => sum + fighter.stats.def, 0) / fighters.length;
      const weakened = elapsed <= weakenedUntil ? 0.92 : 1;
      const incoming = Math.max(1, Math.round(stage.enemyAttack * weakened - averageDef * 0.38));
      partyHp = Math.max(0, partyHp - incoming);
      events.push({ type: 'enemy', at: elapsed, damage: incoming, partyHp });
      nextEnemyAttack += stage.boss ? 1.15 : 1.45;
    }
    elapsed += GAME_RULES.battleTickMs / 1000;
  }

  return {
    seed,
    victory: enemyHp <= 0,
    duration: Number(Math.min(elapsed, stage.duration).toFixed(2)),
    enemyHp,
    enemyMaxHp: stage.enemyHp,
    partyHp: Math.round(partyHp),
    partyMaxHp: Math.round(partyMaxHp),
    events,
    damageByCard: fighters.map((fighter) => ({ id: fighter.card.id, damage: fighter.damage })),
    synergy,
  };
}
