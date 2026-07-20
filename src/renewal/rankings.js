export const COMBAT_RANKING_RULES = {
  population: 1500,
  visibleCount: 50,
};

const FEATURED_NAMES = [
  '꺼내먹어요e', '빙하.', 'Mstz_손실바', 'TayK', 'HyuN:9',
  'Calm_벌초', '오랜ㄴr무', '모야!', '캄사탄', '비타밍500',
  '브레인', 'Aerys', '죽한연', '스타트아토', '억타구경꾼',
  '사랑해요형', 'Calm_Jm~', '콩맛두유', '아르헨_', 'Calm_별',
];

export const COMBAT_POWER_LEADERS = Array.from({ length: 50 }, (_, index) => ({
  nickname: FEATURED_NAMES[index] ?? `CALM_RANKER_${String(index + 1).padStart(2, '0')}`,
  power: 450_000 - index * 8_500,
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
