export const BALANCE_VERSION = '2026.07.18-random-loot-1';

export const RARITY_ORDER = ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'];

export const RARITIES = {
  F: { multiplier: 1, color: '#89939b' },
  E: { multiplier: 1.12, color: '#58b97a' },
  D: { multiplier: 1.26, color: '#4aa8d8' },
  C: { multiplier: 1.42, color: '#7f79df' },
  B: { multiplier: 1.62, color: '#bb69e8' },
  A: { multiplier: 1.86, color: '#ef5f83' },
  S: { multiplier: 2.15, color: '#ff9b3f' },
  SS: { multiplier: 2.52, color: '#ffd449' },
  SSS: { multiplier: 3, color: '#d7ff35' },
  EX: { multiplier: 0, color: '#f7f7f2', displayOnly: true },
};

export const ARCHETYPES = {
  quick: { label: '속공', atk: 0.9, hp: 0.94, def: 0.9, speed: 1.28, crit: 0.05 },
  heavy: { label: '강타', atk: 1.28, hp: 1.04, def: 1, speed: 0.78, critDamage: 0.2 },
  combo: { label: '연타', atk: 0.96, hp: 0.96, def: 0.94, speed: 1.12, multiHit: 1.1 },
  area: { label: '광역', atk: 1.04, hp: 0.98, def: 0.94, speed: 0.94, area: 1.18 },
  boss: { label: '보스', atk: 1.08, hp: 1.03, def: 1, speed: 0.91, bossDamage: 1.28 },
  amplify: { label: '증폭', atk: 1.02, hp: 0.95, def: 0.92, speed: 1, crit: 0.09, amplify: 0.04 },
  weaken: { label: '약화', atk: 0.92, hp: 1.02, def: 1.02, speed: 1.03, weaken: 0.08 },
  sustain: { label: '생존', atk: 0.91, hp: 1.24, def: 1.18, speed: 0.88, recovery: 0.08 },
};

export const ENHANCEMENT = {
  // nolevel-1: 강화가 카드 전투력 성장의 주축. 0성(1.0) → 9성(3.0).
  statMultipliers: [1, 1.12, 1.27, 1.44, 1.63, 1.85, 2.1, 2.38, 2.7, 3.0],
  baseSuccessRates: [100, 100, 100, 100, 80, 70, 60, 50, 40, 30],
  destroyRates: [0, 0, 0, 0, 0, 0, 0, 3, 8, 15],
  rarityPenalties: { F: 0, E: 2, D: 4, C: 6, B: 8, A: 10, S: 12, SS: 15, SSS: 18 },
  expRequirements: [100, 180, 300, 480, 720, 1000, 1400, 1900, 2500, 0],
  plusNinePointCost: 5000,
  // nolevel-1: 파괴 판정 시 본카드는 유지되고 강화 수치(exp 포함)만 0으로 리셋된다.
  // 카드 소멸 없음. app.js의 destroy 분기에서 cardCopies를 차감하지 않는다.
  resetOnDestroy: true,
};

export const MATERIAL_RULES = {
  F: [{ rarity: 'F', count: 1 }],
  E: [{ rarity: 'F', count: 3 }],
  D: [{ rarity: 'E', count: 3 }],
  C: [{ rarity: 'D', count: 3 }],
  B: [{ rarity: 'C', count: 3 }],
  A: [{ rarity: 'B', count: 3 }],
  S: [{ rarity: 'A', count: 3 }],
  SS: [{ rarity: 'S', count: 3 }],
  SSS: [{ rarity: 'SS', count: 3 }, { rarity: 'SSS', count: 1 }],
};

export const PACKS = {
  general: {
    name: '일반 보급팩', price: 50, count: 3,
    rates: { F: 32, E: 27, D: 20, C: 12, B: 6, A: 2.856, S: 0.12, SS: 0.018, SSS: 0.006 },
  },
  elite: {
    name: '정예 보급팩', price: 150, count: 4,
    rates: { F: 20, E: 22, D: 22, C: 16, B: 11, A: 8.478, S: 0.42, SS: 0.09, SSS: 0.012 },
  },
  premium: {
    name: '프리미엄 보급팩', price: 500, count: 4,
    rates: { F: 9, E: 14, D: 19.5, C: 21, B: 18, A: 17.2, S: 1.0, SS: 0.25, SSS: 0.05 },
  },
  race: {
    name: '종족 보급팩', price: 100, count: 3,
    rates: { F: 38, E: 30, D: 18, C: 9, B: 4, A: 0.9658, S: 0.03, SS: 0.0036, SSS: 0.0006 },
  },
};

export const SUPPORT_PACK = {
  name: '작전 지원 보급팩', price: 150, tenPrice: 1500,
  items: {
    energySmall: 19, energyMedium: 11, energyLarge: 3,
    enhance5: 16, enhance10: 6, destructionGuard: 1,
    cardExpPotion: 8, exp30m: 14, exp2h: 9,
    generalTicket: 6, eliteTicket: 3.5, raceTicket: 2, premiumTicket: 0.5,
    adventureRunReset: 0.25, quickBattleReset: 0.75,
  },
  rareItems: [
    'energyLarge', 'enhance10', 'destructionGuard', 'exp2h',
    'generalTicket', 'eliteTicket', 'raceTicket', 'premiumTicket',
    'adventureRunReset', 'quickBattleReset',
  ],
  guaranteeRates: {
    energyLarge: 10, enhance10: 24, destructionGuard: 3, exp2h: 28,
    generalTicket: 15, eliteTicket: 8, raceTicket: 5, premiumTicket: 2,
    adventureRunReset: 1, quickBattleReset: 4,
  },
};

export const SUPPORT_ITEMS = {
  energySmall: { name: '전술 배터리 S', category: '행동력', effect: '행동력 +20', energy: 20 },
  energyMedium: { name: '전술 배터리 M', category: '행동력', effect: '행동력 +50', energy: 50 },
  energyLarge: { name: '전술 배터리 L', category: '행동력', effect: '행동력 +120', energy: 120 },
  enhance5: { name: '강화 촉진제', category: '강화', effect: '성공률 +5%p' },
  enhance10: { name: '고순도 강화 촉진제', category: '강화', effect: '성공률 +10%p' },
  destructionGuard: { name: '파괴 차단제', category: '강화', effect: '파괴 1회 차단' },
  cardExpPotion: { name: '카드 EXP 포션', category: '경험치', effect: '선택 카드 EXP +300', cardExp: 300 },
  exp30m: { name: '경험 신호 증폭제', category: '경험치', effect: '카드 EXP +50% · 30분', durationMinutes: 30 },
  exp2h: { name: '고출력 경험 신호 증폭제', category: '경험치', effect: '카드 EXP +50% · 2시간', durationMinutes: 120 },
  generalTicket: { name: '일반 카드팩 교환권', category: '교환권', effect: '일반팩 1개', pack: 'general' },
  eliteTicket: { name: '정예 카드팩 교환권', category: '교환권', effect: '정예팩 1개', pack: 'elite' },
  raceTicket: { name: '종족 선택팩 교환권', category: '교환권', effect: '종족팩 1개', pack: 'race' },
  premiumTicket: { name: '프리미엄 카드팩 교환권', category: '교환권', effect: '프리미엄팩 1개', pack: 'premium' },
  adventureRunReset: { name: '모험 시작 초기화권', category: '초기화', effect: '모험 시작 횟수 3회 복구', reset: 'adventureRuns' },
  quickBattleReset: { name: '빠른 전투 초기화권', category: '초기화', effect: '오늘 빠른 전투 횟수 3회 복구', reset: 'quickBattle' },
};

export const BONUS_DROP_RULES = {
  itemWeights: {
    energySmall: 24, energyMedium: 14, energyLarge: 4,
    enhance5: 18, enhance10: 6, destructionGuard: 1,
    cardExpPotion: 14, exp30m: 12, exp2h: 5,
    adventureRunReset: 1, quickBattleReset: 1,
  },
  packWeights: {
    generalTicket: 55, eliteTicket: 27, raceTicket: 15, premiumTicket: 3,
  },
  adventureTiers: [
    { minClearedStages: 1, dropRate: 0.18, packShare: 0.08 },
    { minClearedStages: 10, dropRate: 0.24, packShare: 0.12 },
    { minClearedStages: 20, dropRate: 0.30, packShare: 0.16 },
    { minClearedStages: 30, dropRate: 0.36, packShare: 0.20 },
    { minClearedStages: 40, dropRate: 0.43, packShare: 0.24 },
    { minClearedStages: 50, dropRate: 0.50, packShare: 0.30 },
  ],
  worldBoss: {
    failed: { dropRate: 0.35, packShare: 0.15 },
    cleared: { dropRate: 0.60, packShare: 0.25 },
  },
};

// nolevel-1: 계정 레벨 스케일링(1.03^(Lv-37), 최대 약 3만 배) 제거.
// 카드 자체 성장(등급 × 강화 3배 × 도감 100% × 시너지)으로 50스테이지를 커버.
// 초반은 기존 진입 난도를 유지하고, 후반의 계정 레벨 의존 구간만 카드 성장폭에 맞춰 압축한다.
export const REGIONS = [
  { id: 1, name: '끊어진 전파도시', code: 'signal-city', hpBase: 590000, attackBase: 3000, bossHp: 1200000, bossAttack: 4000 },
  { id: 2, name: '침묵한 중계기지', code: 'relay-base', hpBase: 1100000, attackBase: 4500, bossHp: 1820000, bossAttack: 6000 },
  { id: 3, name: '검게 물든 스튜디오', code: 'black-studio', hpBase: 1700000, attackBase: 6500, bossHp: 2800000, bossAttack: 8500 },
  { id: 4, name: '폭주한 데이터 요새', code: 'data-fortress', hpBase: 2500000, attackBase: 9000, bossHp: 4000000, bossAttack: 11000 },
  { id: 5, name: '악플 코어 심층부', code: 'malice-core', hpBase: 4200000, attackBase: 12500, bossHp: 9500000, bossAttack: 21000 },
];

const ENEMY_TYPES = ['crawler', 'jammer', 'leech', 'crusher'];

export const STAGES = REGIONS.flatMap((region, regionIndex) => Array.from({ length: 10 }, (_, stageIndex) => {
  const stageNumber = stageIndex + 1;
  const globalNumber = regionIndex * 10 + stageNumber;
  const boss = stageNumber === 10;
  const firstRegion = region.id === 1;
  return {
    id: `${region.id}-${stageNumber}`,
    region: region.name,
    regionCode: region.code,
    regionIndex,
    stageNumber,
    globalNumber,
    enemyType: boss ? 'boss' : ENEMY_TYPES[(stageIndex + regionIndex) % ENEMY_TYPES.length],
    enemyCount: boss ? 1 : Math.min(7, 4 + Math.floor(stageNumber / 3)),
    enemyHp: Math.round(boss
      ? region.bossHp
      : region.hpBase * Math.pow(firstRegion ? 1.08 : 1.025, stageIndex)),
    enemyAttack: Math.round(boss
      ? region.bossAttack
      : region.attackBase * Math.pow(firstRegion ? 1.03 : 1.02, stageIndex)),
    duration: boss ? 40 + regionIndex * 3 : 30 + regionIndex * 2 + (firstRegion ? stageIndex : 0),
    rewardPoints: 18 + globalNumber * 4,
    boss,
  };
}));

export const GAME_RULES = {
  formationSize: 5,
  battleTickMs: 250,
  playbackScale: 0.22,
  baseCardStats: { atk: 3600, hp: 14500, def: 620, speed: 1, crit: 0.08, critDamage: 1.5 },
  // nolevel-1: 종족 시너지 강화. 카드 자체 성장 분량 확대.
  raceSynergy: {
    3: { atk: 1.05, hp: 1.05 },
    5: { atk: 1.12, hp: 1.12 },
  },
};

export const ADVENTURE_RULES = {
  maxRunsPerWindow: 3,
  runWindowMs: 4 * 60 * 60 * 1000,
  runReward: {
    pointsBasePerStage: 20,
    pointsGrowthPerStage: 5.5,
    maxPointsPerRun: 8000,
    cardExpPerClearedStage: 1,
  },
};

export const REWARD_RULES = {
  maxStage: 50,
  maxActionEnergy: 120,
  offlineCapHours: 24,
  quickBattleHours: 2,
  quickBattleEnergy: 20,
  // 이름과 달리 달력 날짜가 아니라 ADVENTURE_RULES.runWindowMs(4시간)와 동일한 롤링 윈도우로 초기화된다.
  quickBattleDailyLimit: 3,
  energyRecoveryMinutes: 6,
  cardExpBasePerMinute: 0.04,
  cardExpPerStage: 0.004,
};

export const COLLECTION_RULES = {
  // nolevel-1: 도감 보너스 상한 50% → 100%, 세부 보너스 2배.
  combatBonusCap: 1.0,
  memberCompletionBonus: 0.0125,
  raceCompletionBonus: 0.05,
  rarityCompletionBonus: 0.025,
  overallMilestones: [0.25, 0.5, 0.75, 1],
  overallCompletionBonus: 0.0375,
  idlePerMilestone: 0.06,
  idlePerRaceCompletion: 0.02,
};

export const MINI_GAME_RULES = {
  energyCost: 10,
  dailyPointCapPerGame: 3000,
  memory: {
    basic: { label: '4×4', pairs: 8, columns: 4, timeLimit: 90, completionReward: 500 },
    advanced: { label: '6×6', pairs: 18, columns: 6, timeLimit: 150, completionReward: 1500 },
  },
  sumTen: { label: '캄몬사과게임', rows: 10, columns: 17, timeLimit: 120, baseReward: 40, rewardPerScore: 1, maxReward: 240 },
};

export const WORLD_BOSS_RULES = {
  eventId: 'noise-zero-local-01',
  name: 'NOISE//ZERO',
  subtitle: '거대 악플 코어',
  timeZone: 'Asia/Seoul',
  scheduleHours: [17, 18, 19, 20],
  // nolevel-1: 새 카드 전투력 스케일에 맞춰 공동 HP·서버 DPS 재튠.
  maxHp: 5_000_000_000,
  battleDuration: 60,
  maxAttempts: 3,
  eventDurationSeconds: 60 * 60,
  raidDurationSeconds: 30 * 60,
  // 30분 전투 종료 시 서버 기여 49.8억. 개인 누적 2,000만이 성공 경계가 된다.
  serverDamagePerSecond: 2_766_667,
  cardExpPerAttempt: 25,
  rewardTiers: [
    { damage: 1, points: 1000, failurePoints: 250, label: '참여' },
    { damage: 2_000_000, points: 2000, failurePoints: 500, label: '200만' },
    { damage: 5_000_000, points: 3500, failurePoints: 1000, label: '500만' },
    { damage: 10_000_000, points: 5500, failurePoints: 2000, label: '1,000만' },
    { damage: 15_000_000, points: 8000, failurePoints: 3000, label: '1,500만' },
    { damage: 20_000_000, points: 10000, failurePoints: 5000, label: '2,000만' },
  ],
};

export const SOOP_RULES = {
  pointsPerBalloon: 3,
};

export const EX_DISTRIBUTION_RULES = {
  enabled: true,
  status: 'adventure-milestones-v1',
  packEligible: false,
  combatEligible: false,
  collectionBonusEligible: false,
  milestones: [
    { clearedStage: 5, cardId: 'group-1' },
    { clearedStage: 10, cardId: 'group-2' },
    { clearedStage: 15, cardId: 'group-3' },
    { clearedStage: 20, cardId: 'group-4' },
    { clearedStage: 25, cardId: 'group-5' },
    { clearedStage: 30, cardId: 'group-6' },
    { clearedStage: 40, cardId: 'group-7' },
    { clearedStage: 50, cardId: 'group-8' },
  ],
};

export const GROWTH_SIMULATION_PROFILES = {
  low: {
    label: '하위 신규 계정', deckStart: 15, startingPoints: 0,
    offlineHoursPerDay: 8, quickBattlesPerDay: 0,
    adventureSessionsPerDay: 1,
    miniGamesPerDay: 4, miniGamePointsPerPlay: 70,
    worldBossAttemptsPerDay: 1, worldBossRewardTier: 0, worldBossDefeated: false,
    packKey: 'general',
    collection: { attack: 0, hp: 0, defense: 0, bossDamage: 0, idle: 0 },
  },
  mid: {
    label: '중위 일반 계정', deckStart: 5, startingPoints: 5000,
    offlineHoursPerDay: 16, quickBattlesPerDay: 1,
    adventureSessionsPerDay: 3,
    miniGamesPerDay: 10, miniGamePointsPerPlay: 90,
    worldBossAttemptsPerDay: 2, worldBossRewardTier: 4, worldBossDefeated: false,
    packKey: 'elite',
    collection: { attack: 0.04, hp: 0.04, defense: 0.04, bossDamage: 0.03, idle: 0.12 },
  },
  high: {
    label: '상위 집중 계정', deckStart: 5, startingPoints: 20000,
    offlineHoursPerDay: 24, quickBattlesPerDay: 3,
    adventureSessionsPerDay: 6,
    miniGamesPerDay: 18, miniGamePointsPerPlay: 120,
    worldBossAttemptsPerDay: 3, worldBossRewardTier: 5, worldBossDefeated: true,
    packKey: 'premium',
    collection: { attack: 0.14, hp: 0.12, defense: 0.12, bossDamage: 0.12, idle: 0.3 },
  },
};

export const BALANCE_GOVERNANCE = {
  locked: [
    'RARITIES', 'GAME_RULES', 'ADVENTURE_RULES', 'ENHANCEMENT', 'MATERIAL_RULES',
    'PACKS', 'SUPPORT_PACK', 'SUPPORT_ITEMS', 'BONUS_DROP_RULES',
    'REWARD_RULES', 'COLLECTION_RULES', 'MINI_GAME_RULES',
    'SOOP_RULES.pointsPerBalloon', 'EX_DISTRIBUTION_RULES',
  ],
  operatorTunable: [
    'WORLD_BOSS_RULES.eventId', 'WORLD_BOSS_RULES.maxHp', 'WORLD_BOSS_RULES.eventDurationSeconds',
    'WORLD_BOSS_RULES.timeZone', 'WORLD_BOSS_RULES.scheduleHours',
    'WORLD_BOSS_RULES.serverDamagePerSecond', 'WORLD_BOSS_RULES.raidDurationSeconds',
    'WORLD_BOSS_RULES.rewardTiers',
  ],
};
