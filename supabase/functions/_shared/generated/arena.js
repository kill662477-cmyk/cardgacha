// 투기장(비동기 PvP) 순수 로직.
// 클라이언트와 서버(Edge)가 같은 함수를 써야 전투 재현 검증이 어긋나지 않는다.
import { ARCHETYPES, ARENA_RULES, GAME_RULES } from './config.js';
import { computeCardStats, getFormationCritAura, getRaceSynergy, simulateBattle } from './battle.js';

// 적이 때리는 간격. battle.js 의 비보스 스테이지 간격과 같아야 환산 공격력이 맞는다.
const ENEMY_ATTACK_INTERVAL_SECONDS = 1.45;

export function arenaTierFor(rating, rank = null) {
  const score = Number(rating);
  const tiers = ARENA_RULES.tiers;
  const grandmaster = tiers[tiers.length - 1];
  // 챌린저는 점수만으로 정해지지 않는다. 그랜드마스터 점수 이상이면서 상위 N등 안에 들어야 한다.
  if (
    Number.isFinite(score) && score >= grandmaster.minRating
    && Number.isInteger(rank) && rank >= 1 && rank <= ARENA_RULES.challengerSlots
  ) return ARENA_RULES.challengerTier;
  let matched = tiers[0];
  for (const tier of tiers) {
    if (Number.isFinite(score) && score >= tier.minRating) matched = tier;
  }
  return matched;
}

export function arenaExpectedScore(rating, opponentRating) {
  return 1 / (1 + 10 ** ((Number(opponentRating) - Number(rating)) / 400));
}

// 승패에 따른 레이팅 변동.
// 방어자는 본인이 고른 판이 아니라 하루에도 수십 번 당하므로 변동폭을 줄여 적용한다.
export function arenaRatingDelta(rating, opponentRating, won, role = 'attacker') {
  const expected = arenaExpectedScore(rating, opponentRating);
  const scale = role === 'defender' ? ARENA_RULES.defenderDeltaScale : 1;
  return Math.round(ARENA_RULES.eloK * scale * ((won ? 1 : 0) - expected));
}

export function applyArenaRating(rating, opponentRating, won, role = 'attacker') {
  const next = Number(rating) + arenaRatingDelta(rating, opponentRating, won, role);
  return Math.max(ARENA_RULES.minRating, next);
}

// 주간 정산 후 시작점 쪽으로 절반 당긴다.
export function arenaSeasonReset(rating) {
  const start = ARENA_RULES.startRating;
  const pulled = start + (Number(rating) - start) / ARENA_RULES.seasonResetDivisor;
  return Math.max(ARENA_RULES.minRating, Math.round(pulled));
}

export function arenaWeeklyReward(rank) {
  const position = Number(rank);
  for (const bracket of ARENA_RULES.weeklyRewards) {
    if (bracket.maxRank == null) return bracket.points;
    if (Number.isInteger(position) && position >= 1 && position <= bracket.maxRank) return bracket.points;
  }
  return 0;
}

// 편성을 "적"으로 환산한다. 전투 엔진은 파티 대 스테이지만 알기 때문에,
// PvP 를 하려면 상대 편성을 enemyHp/enemyAttack 을 가진 스테이지로 바꿔야 한다.
export function formationAsStage(formation, bonuses = {}, stageId = 'arena') {
  const synergy = getRaceSynergy(formation);
  const combatBonuses = { ...bonuses, crit: (bonuses.crit ?? 0) + getFormationCritAura(formation) };
  let hp = 0;
  let damagePerSecond = 0;
  for (const card of formation) {
    const stats = computeCardStats(card, combatBonuses);
    if (!stats) continue;
    const trait = ARCHETYPES[card.archetype] ?? {};
    hp += stats.hp * synergy.hp;
    // 치명타 기대값과 연타·광역 계수까지 반영해야 실제 화력과 어긋나지 않는다.
    // 보스 계수는 상대가 보스가 아니므로 뺀다.
    const critical = 1 + stats.crit * (stats.critDamage - 1);
    const hitBonus = trait.multiHit ?? trait.area ?? 1;
    damagePerSecond += stats.atk * stats.speed * critical * hitBonus * synergy.atk;
  }
  return {
    id: stageId,
    mode: 'arena',
    boss: false,
    enemyHp: Math.max(1, Math.round(hp)),
    enemyAttack: Math.max(1, Math.round(damagePerSecond * ENEMY_ATTACK_INTERVAL_SECONDS)),
    duration: ARENA_RULES.battleDuration,
  };
}

// 한쪽 시점의 전투 결과. 상대를 스테이지로 바꿔 기존 엔진으로 돌린다.
function sideResult(formation, bonuses, opponentStage) {
  const result = simulateBattle(formation, opponentStage, bonuses);
  const dealt = opponentStage.enemyHp - result.enemyHp;
  return {
    victory: result.victory,
    duration: result.duration,
    damageRatio: opponentStage.enemyHp > 0 ? dealt / opponentStage.enemyHp : 0,
    partyRatio: result.partyMaxHp > 0 ? result.partyHp / result.partyMaxHp : 0,
  };
}

// 비동기 매치 판정. 양쪽을 각자 돌린 뒤 비교한다.
// 같은 입력이면 항상 같은 결과가 나와야 서버 재현 검증이 성립한다.
export function resolveArenaMatch({
  attacker,
  defender,
  attackerBonuses = {},
  defenderBonuses = {},
  matchId = 'arena-match',
}) {
  if (!Array.isArray(attacker) || attacker.length !== GAME_RULES.formationSize) {
    throw new Error(`Attacker formation must contain ${GAME_RULES.formationSize} cards.`);
  }
  if (!Array.isArray(defender) || defender.length !== GAME_RULES.formationSize) {
    throw new Error(`Defender formation must contain ${GAME_RULES.formationSize} cards.`);
  }
  // 스테이지 id 가 전투 시드에 들어간다. 매치마다 다른 id 를 써야 같은 상대와
  // 반복해서 붙어도 결과가 복사되지 않는다.
  const defenderStage = formationAsStage(defender, defenderBonuses, `${matchId}:d`);
  const attackerStage = formationAsStage(attacker, attackerBonuses, `${matchId}:a`);
  const attackerSide = sideResult(attacker, attackerBonuses, defenderStage);
  const defenderSide = sideResult(defender, defenderBonuses, attackerStage);

  let attackerWon;
  let reason;
  if (attackerSide.victory !== defenderSide.victory) {
    // 한쪽만 상대를 눕혔다.
    attackerWon = attackerSide.victory;
    reason = 'knockout';
  } else if (attackerSide.victory) {
    // 둘 다 눕혔으면 더 빨리 끝낸 쪽. 시간까지 같으면 남은 체력 비율로 가른다.
    if (attackerSide.duration !== defenderSide.duration) {
      attackerWon = attackerSide.duration < defenderSide.duration;
      reason = 'speed';
    } else {
      attackerWon = attackerSide.partyRatio >= defenderSide.partyRatio;
      reason = 'survival';
    }
  } else {
    // 둘 다 못 눕혔으면 더 많이 깎은 쪽.
    attackerWon = attackerSide.damageRatio >= defenderSide.damageRatio;
    reason = 'damage';
  }

  return {
    matchId,
    attackerWon,
    reason,
    attacker: attackerSide,
    defender: defenderSide,
  };
}
