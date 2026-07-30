export const BALANCE_VERSION = '2026.07.30-hell10-worldboss-retune-2';

export const RARITY_ORDER = ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'];

export const RARITIES = {
  F: { multiplier: 1, color: '#89939b' },
  E: { multiplier: 1.12, color: '#58b97a' },
  D: { multiplier: 1.26, color: '#4aa8d8' },
  C: { multiplier: 1.42, color: '#7f79df' },
  B: { multiplier: 1.62, color: '#bb69e8' },
  A: { multiplier: 1.86, color: '#ef5f83' },
  S: { multiplier: 2.15, color: '#ff9b3f' },
  SS: { multiplier: 2.9, color: '#ffd449' },
  SSS: { multiplier: 4.6, color: '#d7ff35' },
  EX: { multiplier: 0, color: '#f7f7f2', displayOnly: true },
};

export const ARCHETYPES = {
  quick: { label: '속공', atk: 0.9, hp: 0.94, def: 0.9, speed: 1.28, crit: 0.05 },
  // 강타: critDamage 는 치명타가 터져야 의미가 있는데 기본 확률이 8% 뿐이라 사실상 죽은 보정이었다.
  // 확률을 20%로 올려 특성이 실제로 작동하게 하고, 그만큼 딜 손실을 atk 로 메운다.
  heavy: { label: '강타', atk: 1.31, hp: 1.04, def: 1, speed: 0.78, crit: 0.12, critDamage: 0.2 },
  combo: { label: '연타', atk: 0.96, hp: 0.96, def: 0.94, speed: 1.12, multiHit: 1.1 },
  area: { label: '광역', atk: 1.04, hp: 0.98, def: 0.94, speed: 0.94, area: 1.5 },
  boss: { label: '보스', atk: 1.08, hp: 1.03, def: 1, speed: 0.91, bossDamage: 2.0 },
  // 증폭: 자기 치명타만 올리던 특성을 파티 전체 치명타 오라로 바꿨다. 강타가 치명타 담당이
  // 되면서 역할이 겹쳤고, 기존 파티 딜 +4%(중첩)는 5장을 다 넣어도 이득이 +0.66%p 뿐이었다.
  // critAura 는 편성 전체에 합산되므로 많이 넣을수록 강해지는 유일한 특성이다.
  amplify: { label: '증폭', atk: 1.02, hp: 0.95, def: 0.92, speed: 1, critAura: 0.15 },
  // 약화는 두 갈래로 작동한다. weaken = 적 공격력 감소, weakenDamage = 적이 받는 피해 증가.
  // 이 게임에는 적 방어력 스탯이 없어(스테이지는 enemyHp/enemyAttack 뿐) '방어력 감소'를
  // 받는 피해 증가로 구현했다. 둘 다 중첩되지 않고 가장 강한 값 하나만 적용된다.
  weaken: { label: '약화', atk: 0.92, hp: 1.02, def: 1.02, speed: 1.03, weaken: 0.15, weakenDamage: 0.10 },
  // 생존: 딜이 연타 대비 67.7% 로 8종 중 최하위였다. 속도를 올리면 회복까지 강해지므로
  // atk 만 올려 딜을 79 수준으로 맞춘다(표시 전투력 86.7 -> 94.8).
  sustain: { label: '생존', atk: 1.06, hp: 1.24, def: 1.18, speed: 0.88, recovery: 0.08 },
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

// 카드 분해. 중복 카드(1장 보존, 잠금 제외)를 소각해 카드 EXP 포션과 뽑기 포인트를
// 개별 확률 굴림으로 얻는다. 등급이 높을수록 드롭 확률/포인트량 상승.
// potionRate/pointsRate: 각 카드 1장당 포션/포인트 드롭 확률 (0~1). 각각 따로 굴림.
// potionItem: 드롭 시 지급할 카드 EXP 포션 아이템 ID.
export const DISMANTLE_RULES = {
  potionItem: 'cardExpPotionLarge',
  keepCopies: 1,
  dropRates: {
    F:   { potionRate: 0.10, pointsRate: 0.10, points: 5 },
    E:   { potionRate: 0.15, pointsRate: 0.15, points: 10 },
    D:   { potionRate: 0.20, pointsRate: 0.20, points: 20 },
    C:   { potionRate: 0.25, pointsRate: 0.25, points: 40 },
    B:   { potionRate: 0.30, pointsRate: 0.30, points: 70 },
    A:   { potionRate: 0.35, pointsRate: 0.35, points: 120 },
    S:   { potionRate: 0.50, pointsRate: 0.50, points: 300 },
    SS:  { potionRate: 0.70, pointsRate: 0.70, points: 800 },
    SSS: { potionRate: 0.90, pointsRate: 0.90, points: 2000 },
  },
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
    energySmall: 14, energyMedium: 8, energyLarge: 2,
    enhance5: 16, enhance10: 6, destructionGuard: 5,
    cardExpPotion: 10, exp30m: 16, exp2h: 9,
    generalTicket: 7, eliteTicket: 3.5, raceTicket: 2, premiumTicket: 0.5,
    adventureRunReset: 0.25, quickBattleReset: 0.75,
  },
  rareItems: [
    'energyLarge', 'enhance10', 'destructionGuard', 'exp2h',
    'generalTicket', 'eliteTicket', 'raceTicket', 'premiumTicket',
    'adventureRunReset', 'quickBattleReset',
  ],
  guaranteeRates: {
    energyLarge: 7, enhance10: 24, destructionGuard: 6, exp2h: 28,
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
  // 이름 주의: 효과값(cardExp)이 정본. Large가 +20, 무印이 +300으로 역전돼 있어
  // 표시 이름만 서로 맞바꿈 (아이템 ID·서버 효과는 불변 — 유저 인벤토리 보존).
  cardExpPotionLarge: { name: '카드 EXP 포션', category: '경험치', effect: '선택 카드 EXP +20', cardExp: 20 },
  cardExpPotion: { name: '농축 카드 EXP 포션', category: '경험치', effect: '선택 카드 EXP +300', cardExp: 300 },
  exp30m: { name: '경험 신호 증폭제', category: '경험치', effect: '카드 EXP +50% · 30분', durationMinutes: 30 },
  exp2h: { name: '고출력 경험 신호 증폭제', category: '경험치', effect: '카드 EXP +50% · 2시간', durationMinutes: 120 },
  generalTicket: { name: '일반 카드팩 교환권', category: '교환권', effect: '일반팩 1개', pack: 'general' },
  eliteTicket: { name: '정예 카드팩 교환권', category: '교환권', effect: '정예팩 1개', pack: 'elite' },
  raceTicket: { name: '종족 선택팩 교환권', category: '교환권', effect: '종족팩 1개', pack: 'race' },
  premiumTicket: { name: '프리미엄 카드팩 교환권', category: '교환권', effect: '프리미엄팩 1개', pack: 'premium' },
  ssCardSelector: { name: 'SS 카드 선택권', category: '선택권', effect: '원하는 SS 카드 1장 선택', cardSelectorRarity: 'SS' },
  sssCardSelector: { name: 'SSS 카드 선택권', category: '선택권', effect: '원하는 SSS 카드 1장 선택', cardSelectorRarity: 'SSS' },
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
  // balance-tune: 5-10 최종 보스를 SS 7강 + 도감 80% 스펙으로 클리어 가능하게 하향
  // (9,500,000 -> 8,250,000). S 9성 풀도감 테스트 덱은 여전히 막힘.
  { id: 5, name: '악플 코어 심층부', code: 'malice-core', hpBase: 4200000, attackBase: 12500, bossHp: 7500000, bossAttack: 16000 },
  // balance-tune: 하드 모험 올클리어 기준을 SSS 올 7강 + 풀도감 스펙에 맞춤.
  // 카드 천장(SSS 4.6배 × 9강 3배) 대비 과튜닝돼 있던 HP를 원래의 약 0.675배로
  // 하드 재밸런싱(2026-07-26). 기준선 = SSS 등급 · 전원 8강 · 올도감.
  // 특성 상향(약화·생존·강타·증폭) 이후 기준 스펙이 10-10 을 제한시간의 66%, 파티 HP 98% 로
  // 통과해 하드가 사실상 무난한 구간이 됐다. 지역별로 HP 는 시간 압박용, 공격력은 생존
  // 압박용으로 따로 올렸다(HP x1.25/1.28/1.32/1.36/1.44, 공격력 x1.15/1.25/1.45/1.65/1.80).
  // 조정 후: SSS+8 올도감이 10-10 을 시간 95% · HP 39% 로 겨우 통과하고, SSS+7 은 35 스테이지,
  // SS+9 는 16 스테이지에서 막힌다. 서포트 없는 딜 5장 편성은 전멸해 편성 구성도 요구된다.
  {
    id: 6, name: '붕괴한 신호 폐허', code: 'void-rift', mode: 'hard',
    hpBase: 8862500, attackBase: 26393, bossHp: 11812500, bossAttack: 24438,
    duration: 46, bossDuration: 56,
  },
  {
    id: 7, name: '심연의 중계 감옥', code: 'abyss-relay', mode: 'hard',
    hpBase: 10803200, attackBase: 30281, bossHp: 14259200, bossAttack: 28156,
    duration: 48, bossDuration: 58,
  },
  {
    id: 8, name: '악몽 송출 스튜디오', code: 'nightmare-studio', mode: 'hard',
    hpBase: 12922800, attackBase: 36975, bossHp: 17820000, bossAttack: 34510,
    duration: 50, bossDuration: 60,
  },
  {
    id: 9, name: '오메가 데이터 성채', code: 'omega-fortress', mode: 'hard',
    hpBase: 15150400, attackBase: 44880, bossHp: 22032000, bossAttack: 41374,
    duration: 52, bossDuration: 62,
  },
  {
    id: 10, name: '지옥 악플 코어', code: 'hell-core', mode: 'hard',
    hpBase: 17985600, attackBase: 48960, bossHp: 27216000, bossAttack: 48195,
    duration: 59, bossDuration: 64,
  },
  // 최종 콘텐츠. Hell10 기준선은 SSS 9강 5장 + 도감 100% + 길드 Lv.10.
  // 역할이 갖춰진 편성만 제한시간 끝자락에 통과하고 SSS 8강은 막히도록 실전 시뮬레이션으로 조정했다.
  {
    id: 11, name: '최후 심판 성역', code: 'hell-final', mode: 'hell',
    hpBase: 24000000, attackBase: 52000, bossHp: 48000000, bossAttack: 50000,
    duration: 66, bossDuration: 78,
  },
];

const ENEMY_TYPES = ['crawler', 'jammer', 'leech', 'crusher'];

export const STAGES = REGIONS.flatMap((region, regionIndex) => Array.from({ length: 10 }, (_, stageIndex) => {
  const stageNumber = stageIndex + 1;
  const globalNumber = regionIndex * 10 + stageNumber;
  const boss = stageNumber === 10;
  const firstRegion = region.id === 1;
  const hard = region.mode === 'hard';
  const hell = region.mode === 'hell';
  return {
    id: `${region.id}-${stageNumber}`,
    displayName: hell ? `Hell${stageNumber}` : `${region.id}-${stageNumber}`,
    region: region.name,
    regionCode: region.code,
    regionIndex,
    stageNumber,
    globalNumber,
    mode: region.mode ?? 'normal',
    hard,
    hell,
    enemyType: boss ? 'boss' : ENEMY_TYPES[(stageIndex + regionIndex) % ENEMY_TYPES.length],
    enemyCount: boss ? 1 : Math.min(7, 4 + Math.floor(stageNumber / 3)),
    enemyHp: Math.round(boss
      ? region.bossHp
      : region.hpBase * Math.pow(hell ? 1.008 : hard ? 1.018 : firstRegion ? 1.08 : 1.025, stageIndex)),
    enemyAttack: Math.round(boss
      ? region.bossAttack
      : region.attackBase * Math.pow(hell ? 1.01 : hard ? 1.012 : firstRegion ? 1.03 : 1.02, stageIndex)),
    duration: hard || hell
      ? (boss ? region.bossDuration : region.duration)
      : (boss ? 40 + regionIndex * 3 : 30 + regionIndex * 2 + (firstRegion ? stageIndex : 0)),
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
  modes: {
    normal: { label: '일반 모험', startStage: 1, endStage: 50, stageCount: 50, unlockStage: 0 },
    hard: { label: '하드 모험', startStage: 51, endStage: 100, stageCount: 50, unlockStage: 50 },
    hell: { label: 'HELL', startStage: 101, endStage: 110, stageCount: 10, unlockStage: 100 },
  },
  runReward: {
    pointsBasePerStage: 20,
    pointsGrowthPerStage: 5.5,
    maxPointsPerRun: 8000,
    cardExpPerClearedStage: 1,
  },
  hardRunReward: {
    minPointsPerRun: 7000,
    maxPointsPerRun: 20000,
    cardExpPerClearedStage: 1,
  },
  hellRunReward: {
    minPointsPerRun: 12000,
    maxPointsPerRun: 25000,
    cardExpPerClearedStage: 2,
  },
};

export const REWARD_RULES = {
  maxStage: 110,
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
  dailyPointCapPerGame: 10000,
  memory: {
    basic: { label: '4×4', pairs: 8, columns: 4, timeLimit: 90, completionReward: 500 },
    advanced: { label: '6×6', pairs: 18, columns: 6, timeLimit: 150, completionReward: 1500 },
  },
  sumTen: { label: '캄몬사과게임', rows: 10, columns: 17, timeLimit: 120, baseReward: 40, rewardPerScore: 17, maxReward: 3000 },
  ladder: {
    label: '운명의 사다리',
    columns: 6,
    rungRows: 10,
    energyCost: 100,
    rewards: [3000, 2000, 1500, 1000, 500, 50],
  },
};

export const WORLD_BOSS_RULES = {
  eventId: 'noise-zero-local-01',
  name: 'NOISE//ZERO',
  subtitle: '거대 악플 코어',
  timeZone: 'Asia/Seoul',
  scheduleHours: [17, 18, 19, 20],
  attackEnergyCost: 10,
  slotTiers: {
    // balance-tune: 서버 자동딜(서버DPS) 완전 폐지 -> 이제 참가자 전원의 합산 딜만으로
    // 처치 여부가 갈린다(0으로 두면 서버RPC가 자동으로 자동딜 0으로 계산, 로직 변경 불필요).
    // maxHp는 지정값(17:110억/18:115억/19:120억/20:130억)으로 고정 -> 참여가 부족한 회차는 실패 가능.
    // 2026-07-26 1차: 특성 상향으로 각 슬롯 +5억(55~70 -> 60~75).
    // 2026-07-26 2차: 17시 실측 최대 개인딜 49.0M -> 54.3M(+11%). 슬롯당 +5억.
    // 2026-07-26 3차: 18시(70억)가 4분 만에 98% 소진돼 후반 슬롯만 크게 올림(19:85억/20:95억).
    // 2026-07-27: 실측 17시 7.1분 / 18시 5.1분 / 19시 13.4분 클리어, 20시 99.0%로 실패.
    //   앞 두 회차가 너무 빨라 크게 올리고, 벽 역할인 뒤쪽은 소폭만 올린다(2026-07-28 적용).
    // difficultyMultiplier는 표시 전용(worldboss-controller 안내 문구)이라 17시 대비 HP 비율로 맞춘다.
    17: {
      title: '신호 요새', name: 'SIGNAL//BASTION', difficultyMultiplier: 1,
      maxHp: 11_000_000_000, serverDamagePerSecond: 0, clearDestructionGuardRate: 0.05,
      image: 'assets/renewal/worldboss/boss-17-signal-bastion.webp',
    },
    18: {
      title: '중계 포식자', name: 'RELAY//DEVOURER', difficultyMultiplier: 1.045,
      maxHp: 11_500_000_000, serverDamagePerSecond: 0, clearDestructionGuardRate: 0.10,
      image: 'assets/renewal/worldboss/boss-18-relay-devourer.webp',
    },
    19: {
      title: '공허 수확자', name: 'VOID//HARVESTER', difficultyMultiplier: 1.091,
      maxHp: 12_000_000_000, serverDamagePerSecond: 0, clearDestructionGuardRate: 0.15,
      image: 'assets/renewal/worldboss/boss-19-void-harvester.webp',
    },
    20: {
      title: '악의 특이점', name: 'MALICE//SINGULARITY', difficultyMultiplier: 1.182,
      maxHp: 13_000_000_000, serverDamagePerSecond: 0, clearDestructionGuardRate: 0.20,
      image: 'assets/renewal/worldboss/boss-20-malice-singularity.webp',
    },
  },
  // nolevel-1: 서버DPS 폐지로 공동 HP가 곧 참가자 합산딜 목표치. 기본값은 17시 슬롯과 동일.
  maxHp: 11_000_000_000,
  battleDuration: 60,
  maxAttempts: 3,
  eventDurationSeconds: 60 * 60,
  raidDurationSeconds: 30 * 60,
  // balance-tune: 서버 자동딜 폐지(0) -> 처치는 순수 참가자 합산딜 vs maxHp 비교로만 결정되어
  // 참여·화력이 부족한 회차는 실패할 수 있다.
  serverDamagePerSecond: 0,
  cardExpPerAttempt: 25,
  // 보상 티어(2026-07-26 재설정). 앵커 = 개인딜 5,000만 -> 30,000P / 6,000만 -> 40,000P.
  // 특성 상향으로 화력이 올라 기존 최고 티어(4,000만 = 30,000P)가 너무 쉬워졌다.
  // 실측(최근 2일 1,320명): 평균 개인딜 31.4M, 최대 49.0M -> 5,000만은 곧 닿고 6,000만은 성장 목표.
  // failurePoints 는 처치 실패 시 지급액이다.
  // 주의: 티어를 늘릴 때 gacha_s2_world_boss_players 의 두 제약을 반드시 확인할 것.
  //   claimed_tier between -1 and 15  (티어 개수 - 1 이 인덱스 상한)
  //   reward_points between 0 and 100000
  // 과거 이 두 제약을 넘겨 보상 수령이 전부 실패한 사고가 두 번 있었다.
  rewardTiers: [
    { damage: 1, points: 1200, failurePoints: 300, label: '참여' },
    { damage: 2_000_000, points: 2500, failurePoints: 600, label: '200만' },
    { damage: 5_000_000, points: 4500, failurePoints: 1200, label: '500만' },
    { damage: 10_000_000, points: 7000, failurePoints: 2000, label: '1,000만' },
    { damage: 20_000_000, points: 12000, failurePoints: 4000, label: '2,000만' },
    { damage: 30_000_000, points: 18000, failurePoints: 6000, label: '3,000만' },
    { damage: 40_000_000, points: 24000, failurePoints: 9000, label: '4,000만' },
    { damage: 50_000_000, points: 30000, failurePoints: 12000, label: '5,000만' },
    { damage: 60_000_000, points: 40000, failurePoints: 15000, label: '6,000만' },
  ],
};

// 길드(PDB-16 M2). 길드원의 일상 플레이가 공헌도(GP)로 쌓이고, 누적 GP로 길드 레벨이 오른다.
// 버프는 길드원 전원에게 상시 적용되며, 무소속 유저를 무력화하지 않도록 상한을 +5% 선으로 묶는다.
export const GUILD_RULES = {
  defaultMemberLimit: 30,
  maxOfficers: 2,
  maxPendingRequests: 3,
  leavePenaltyDays: 3,
  // 명령 1회당 지급하는 공헌도. 기존 RPC 를 고치지 않고 감사 로그 트리거로 적립하므로
  // "스테이지 몇 개" 같은 세부 결과가 아니라 명령 단위로 센다.
  gpPerCommand: {
    finishAdventureRun: 5,
    claimQuickBattle: 5,
    finishMinigame: 2,
    playLadder: 2,
    attackWorldBoss: 10,
    attackGuildRaid: 15,
  },
  // 소수 인원이 혼자 레벨을 올리지 못하도록 하루 개인 적립 상한을 둔다.
  dailyGpCapPerMember: 200,
  // 포인트 기부로 공헌도를 보충할 수 있다(인플레 완화 밸브).
  donation: { pointsPerGp: 500, dailyPointCap: 50_000 },
  // 길드 레이드(PDB-16 3.3). 월드보스와 같은 합산딜 구조이나 보상 구조가 다르다.
  // 처치하면 참여 여부와 무관하게 길드원 전원이 보상을 받고, 대신 난이도를 다수 참여
  // 전제로 잡는다. HP 는 참여자 수가 아니라 "활동 길드원 수" 기준으로 고정해야
  // 참여가 적을수록 어려워진다(참여자 비례로 두면 몇 명이 오든 난이도가 같아진다).
  raid: {
    scheduleIsoDays: [3, 6], // 수요일, 토요일
    hourKst: 21,
    raidDurationSeconds: 30 * 60,
    resultDurationSeconds: 30 * 60,
    maxAttempts: 3,
    // 월드보스 실측(시도당 약 1,000만 딜 × 인당 3회)에 목표 참여율 0.7 을 곱한 값.
    hpPerActiveMember: 21_000_000,
    activeWindowDays: 7,
    successPoints: 50_000,
    failurePoints: 15_000,
  },
  // 주간 공동목표(PDB-16 3.2). 월요일 00:00 KST 리셋.
  // 목표치는 인원 비례이며(기준 30명), 1인이 목표의 8% 넘게 기여해도 그 초과분은
  // 집계하지 않는다. 소수 고인물이 혼자 끝내지 못하게 하고 라이트 유저의 기여 여지를 남긴다.
  weekly: {
    memberBaseline: 30,
    memberContributionCap: 0.08,
    rewardPoints: 80_000,
    goals: [
      { key: 'adventure', label: '모험 클리어', source: 'adventure', perMember: 10 },
      { key: 'minigame', label: '미니게임 플레이', source: 'minigame', perMember: 7 },
      { key: 'worldboss', label: '월드보스 공격', source: 'worldboss', perMember: 4 },
    ],
  },
  levels: [
    { level: 1, requiredGp: 0, memberLimit: 30, atk: 0, hp: 0, def: 0, points: 0 },
    { level: 2, requiredGp: 3_000, memberLimit: 40, atk: 0.02, hp: 0, def: 0, points: 0 },
    { level: 3, requiredGp: 8_000, memberLimit: 50, atk: 0.02, hp: 0.02, def: 0, points: 0 },
    { level: 4, requiredGp: 15_000, memberLimit: 60, atk: 0.03, hp: 0.02, def: 0.02, points: 0 },
    { level: 5, requiredGp: 25_000, memberLimit: 60, atk: 0.03, hp: 0.03, def: 0.03, points: 0 },
    { level: 6, requiredGp: 36_000, memberLimit: 60, atk: 0.04, hp: 0.03, def: 0.03, points: 0 },
    { level: 7, requiredGp: 50_000, memberLimit: 60, atk: 0.04, hp: 0.04, def: 0.03, points: 0.03 },
    { level: 8, requiredGp: 70_000, memberLimit: 60, atk: 0.04, hp: 0.04, def: 0.04, points: 0.03 },
    { level: 9, requiredGp: 92_000, memberLimit: 60, atk: 0.05, hp: 0.04, def: 0.04, points: 0.04 },
    { level: 10, requiredGp: 120_000, memberLimit: 60, atk: 0.05, hp: 0.05, def: 0.04, points: 0.05 },
  ],
};

export function guildLevelFor(totalGp) {
  const gp = Number.isFinite(totalGp) ? totalGp : 0;
  let current = GUILD_RULES.levels[0];
  for (const tier of GUILD_RULES.levels) {
    if (gp >= tier.requiredGp) current = tier;
    else break;
  }
  return current;
}

export const SOOP_RULES = {
  pointsPerBalloon: 5,
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
    'WORLD_BOSS_RULES.attackEnergyCost', 'WORLD_BOSS_RULES.slotTiers',
    'WORLD_BOSS_RULES.serverDamagePerSecond', 'WORLD_BOSS_RULES.raidDurationSeconds',
    'WORLD_BOSS_RULES.rewardTiers',
  ],
};
