export const COMBAT_RANKING_RULES = {
  population: 1500,
  visibleCount: 20,
};

const FEATURED_NAMES = [
  '전파도시_루키', 'Fresh민트', 'Calm_브로커', '암흑신호', 'MSTZ_손실바',
  '테란반장', 'ZERG_SIGNAL', '푸른수정탑', '김치신호', 'NOISE_CUTTER',
];

export const COMBAT_POWER_LEADERS = Array.from({ length: 50 }, (_, index) => ({
  nickname: FEATURED_NAMES[index] ?? `CALM_RANKER_${String(index + 1).padStart(2, '0')}`,
  power: 928_540 - index * 6_080,
}));

export function buildCombatPowerRanking(nickname, combatPower, population = COMBAT_RANKING_RULES.population) {
  const safePopulation = Math.max(COMBAT_POWER_LEADERS.length, Math.floor(Number(population) || COMBAT_RANKING_RULES.population));
  const power = Math.max(0, Math.floor(Number(combatPower) || 0));
  const higherFeatured = COMBAT_POWER_LEADERS.filter((entry) => entry.power > power).length;
  let rank;
  if (higherFeatured < COMBAT_POWER_LEADERS.length) {
    rank = higherFeatured + 1;
  } else {
    const boundary = COMBAT_POWER_LEADERS.at(-1).power;
    const ratio = Math.min(1, power / boundary);
    rank = COMBAT_POWER_LEADERS.length + 1
      + Math.floor((1 - Math.pow(ratio, 0.75)) * (safePopulation - COMBAT_POWER_LEADERS.length - 1));
  }
  rank = Math.max(1, Math.min(safePopulation, rank));
  const topPercent = Math.max(0.1, rank / safePopulation * 100);
  const topFiftyPower = COMBAT_POWER_LEADERS.at(-1).power;
  const leaders = [...COMBAT_POWER_LEADERS, { nickname, power, mine: true }]
    .sort((left, right) => right.power - left.power)
    .slice(0, COMBAT_RANKING_RULES.visibleCount)
    .map((entry, index) => ({ ...entry, rank: index + 1 }));
  return {
    population: safePopulation,
    player: { nickname, power, rank, topPercent },
    leaders,
    topFiftyPower,
    powerToTopFifty: Math.max(0, topFiftyPower - power),
  };
}
