import fs from 'node:fs';
import {
  BALANCE_VERSION,
  ENHANCEMENT,
  GROWTH_SIMULATION_PROFILES,
  MINI_GAME_RULES,
  PACKS,
  RARITY_ORDER,
  REWARD_RULES,
  STAGES,
  WORLD_BOSS_RULES,
} from '../src/renewal/config.js';
import { computeFormationPower, simulateBattle } from '../src/renewal/battle.js';
import { calculateAdventureRunReward } from '../src/renewal/adventure.js';
import { getEnhancementOdds, MATERIAL_RULES } from '../src/renewal/enhancement.js';
import { calculateIdleReward, cardExpRequired } from '../src/renewal/rewards.js';

const demoCards = JSON.parse(fs.readFileSync(new URL('../data/renewal-demo-cards.json', import.meta.url), 'utf8'));
const checkpoints = new Set([1, 7, 18, 30]);

function emptyRarityPool() {
  return Object.fromEntries(RARITY_ORDER.map((rarity) => [rarity, 0]));
}

function addExpectedDrops(target, pack, purchases) {
  Object.entries(pack.rates).forEach(([rarity, rate]) => {
    target[rarity] = (target[rarity] ?? 0) + purchases * pack.count * rate / 100;
  });
}

function sumRates(rates) {
  return Object.values(rates).reduce((sum, value) => sum + value, 0);
}

function clearableStages(deck, bonuses) {
  let cleared = 0;
  for (const stage of STAGES) {
    if (!simulateBattle(deck, stage, bonuses).victory) break;
    cleared += 1;
  }
  return cleared;
}

function addCardExperience(deck, expByCard, gainedExp) {
  deck.forEach((card) => {
    const required = cardExpRequired(card.enhancement ?? 0);
    if (required <= 0) return;
    expByCard[card.id] = Math.min(required, (expByCard[card.id] ?? card.exp ?? 0) + gainedExp);
  });
}

function expectedMaterialCost(card) {
  const rule = MATERIAL_RULES[card.rarity]?.[0];
  if (!rule) return null;
  const successRate = Math.max(1, getEnhancementOdds(card).success) / 100;
  return { rarity: rule.rarity, count: rule.count / successRate };
}

function enhanceReadyCards(deck, expByCard, materialPool, availablePoints) {
  let points = availablePoints;
  let upgrades = 0;
  [...deck]
    .sort((left, right) => (left.enhancement ?? 0) - (right.enhancement ?? 0))
    .forEach((card) => {
      const enhancement = card.enhancement ?? 0;
      if (enhancement >= 9) return;
      const requiredExp = cardExpRequired(enhancement);
      const material = expectedMaterialCost(card);
      const pointCost = enhancement + 1 === 9 ? ENHANCEMENT.plusNinePointCost : 0;
      if (!material || (expByCard[card.id] ?? 0) < requiredExp) return;
      if ((materialPool[material.rarity] ?? 0) + 1e-9 < material.count || points < pointCost) return;
      materialPool[material.rarity] -= material.count;
      points -= pointCost;
      card.enhancement = enhancement + 1;
      card.exp = 0;
      expByCard[card.id] = 0;
      upgrades += 1;
    });
  return { points, upgrades };
}

function simulateProfile(key, profile) {
  const deck = demoCards.slice(profile.deckStart, profile.deckStart + 5)
    .map((card) => ({ ...card, enhancement: 0, exp: 0 }));
  const pack = PACKS[profile.packKey];
  const dailyEnergyUse = profile.quickBattlesPerDay * REWARD_RULES.quickBattleEnergy
    + profile.miniGamesPerDay * MINI_GAME_RULES.energyCost;
  const dailyNaturalEnergy = 24 * 60 / REWARD_RULES.energyRecoveryMinutes;
  if (dailyEnergyUse > dailyNaturalEnergy) {
    throw new Error(`${key} profile uses ${dailyEnergyUse} energy but natural daily recovery is ${dailyNaturalEnergy}.`);
  }

  let clearedStage = clearableStages(deck, profile.collection);
  let points = profile.startingPoints;
  let pointIncome = 0;
  let pointSpent = 0;
  let packPurchases = 0;
  let cardExpSupply = 0;
  let battleAttempts = 0;
  let enhancementSuccesses = 0;
  let completionDay = clearedStage === STAGES.length ? 0 : null;
  const expectedDrops = emptyRarityPool();
  const materialPool = emptyRarityPool();
  const expByCard = Object.fromEntries(deck.map((card) => [card.id, card.exp ?? 0]));
  deck.forEach((card) => { materialPool[card.rarity] += Math.max(0, (card.copies ?? 1) - 1); });
  const snapshots = [];

  for (let day = 1; day <= 30; day += 1) {
    const stageForReward = Math.max(1, Math.min(STAGES.length, clearedStage || 1));
    const offline = calculateIdleReward(profile.offlineHoursPerDay * 60 * 60 * 1000, stageForReward, {
      idleBonus: profile.collection.idle,
    });
    const quick = calculateIdleReward(
      profile.quickBattlesPerDay * REWARD_RULES.quickBattleHours * 60 * 60 * 1000,
      stageForReward,
      { idleBonus: profile.collection.idle },
    );
    let dailyCardExp = offline.cardExp + quick.cardExp
      + profile.worldBossAttemptsPerDay * WORLD_BOSS_RULES.cardExpPerAttempt;

    const worldBossTier = WORLD_BOSS_RULES.rewardTiers[profile.worldBossRewardTier];
    const miniGamePoints = Math.min(
      MINI_GAME_RULES.dailyPointCapPerGame * 2,
      profile.miniGamesPerDay * profile.miniGamePointsPerPlay,
    );
    const worldBossPoints = profile.worldBossDefeated ? worldBossTier.points : worldBossTier.failurePoints;
    const fixedDailyPoints = miniGamePoints + worldBossPoints;
    points += fixedDailyPoints;
    pointIncome += fixedDailyPoints;

    for (let session = 0; session < profile.adventureSessionsPerDay; session += 1) {
      const runClearedStages = clearableStages(deck, profile.collection);
      battleAttempts += Math.min(STAGES.length, runClearedStages + (runClearedStages < STAGES.length ? 1 : 0));
      clearedStage = Math.max(clearedStage, runClearedStages);
      const runReward = calculateAdventureRunReward(runClearedStages);
      points += runReward.points;
      pointIncome += runReward.points;
      dailyCardExp += runReward.cardExp;
    }

    cardExpSupply += dailyCardExp;
    addCardExperience(deck, expByCard, dailyCardExp);
    const enhancement = enhanceReadyCards(deck, expByCard, materialPool, points);
    pointSpent += points - enhancement.points;
    points = enhancement.points;
    enhancementSuccesses += enhancement.upgrades;

    const purchases = Math.floor(points / pack.price);
    if (purchases > 0) {
      const cost = purchases * pack.price;
      points -= cost;
      pointSpent += cost;
      packPurchases += purchases;
      addExpectedDrops(expectedDrops, pack, purchases);
      addExpectedDrops(materialPool, pack, purchases);
    }

    clearedStage = Math.max(clearedStage, clearableStages(deck, profile.collection));
    if (clearedStage === STAGES.length && completionDay === null) completionDay = day;

    if (checkpoints.has(day)) {
      snapshots.push({
        day,
        clearedStage,
        nextStage: clearedStage >= STAGES.length ? 'COMPLETE' : STAGES[clearedStage].id,
        formationPower: computeFormationPower(deck, profile.collection),
        enhancements: deck.map((card) => card.enhancement ?? 0),
        enhancementSuccesses,
        pointIncome,
        pointSpent,
        pointBalance: points,
        packPurchases,
        cardsOpened: packPurchases * pack.count,
        expectedSPlus: expectedDrops.S + expectedDrops.SS + expectedDrops.SSS,
        expectedSSS: expectedDrops.SSS,
        cardExpSupply,
        battleAttempts,
      });
    }
  }

  return {
    key,
    label: profile.label,
    assumptions: {
      pack: pack.name,
      startingPoints: profile.startingPoints,
      offlineHoursPerDay: profile.offlineHoursPerDay,
      adventureSessionsPerDay: profile.adventureSessionsPerDay,
      quickBattlesPerDay: profile.quickBattlesPerDay,
      miniGamesPerDay: profile.miniGamesPerDay,
      worldBossAttemptsPerDay: profile.worldBossAttemptsPerDay,
      worldBossResult: profile.worldBossDefeated ? 'clear' : 'failed',
      bonusLootIncluded: false,
      dailyEnergyUse,
      dailyNaturalEnergy,
      enhancementModel: 'card EXP cap + expected duplicate cost adjusted by success rate; +7~+9 destruction guard assumed',
      deckReplacementIncluded: false,
      soopPointsIncluded: false,
    },
    snapshots,
    completionDay,
    expectedDrops: Object.fromEntries(Object.entries(expectedDrops).map(([rarity, value]) => [rarity, Number(value.toFixed(4))])),
  };
}

Object.entries(PACKS).forEach(([key, pack]) => {
  if (Math.abs(sumRates(pack.rates) - 100) > 1e-9) throw new Error(`${key} card pack rates do not total 100%.`);
});

const profiles = Object.entries(GROWTH_SIMULATION_PROFILES).map(([key, profile]) => simulateProfile(key, profile));
const byKey = Object.fromEntries(profiles.map((profile) => [profile.key, profile]));
if (process.env.RENEWAL_SIMULATION_INSPECT !== '1' && (byKey.high.completionDay === null || byKey.high.completionDay < 10 || byKey.high.completionDay > 18)) {
  throw new Error(`High profile completion target is day 10-18; actual ${byKey.high.completionDay ?? 'incomplete'}.`);
}
if (process.env.RENEWAL_SIMULATION_INSPECT !== '1' && (byKey.mid.completionDay === null || byKey.mid.completionDay < 24 || byKey.mid.completionDay > 30)) {
  throw new Error(`Mid profile completion target is day 24-30; actual ${byKey.mid.completionDay ?? 'incomplete'}.`);
}
if (process.env.RENEWAL_SIMULATION_INSPECT !== '1' && byKey.low.completionDay !== null) {
  throw new Error(`Low profile must remain incomplete after 30 days; actual day ${byKey.low.completionDay}.`);
}

console.log(JSON.stringify({
  balanceVersion: BALANCE_VERSION,
  generatedAt: new Date().toISOString(),
  model: 'deterministic card-growth expected-value projection; SOOP donations and deck replacement excluded',
  profiles,
}, null, 2));
