// 월드보스 운영 수치의 단일 소스.
// 밸런스 조정은 이 파일, 새 마이그레이션, 관련 테스트만 수정한다.
// config.js와 Edge 생성본을 직접 함께 편집하지 말고 npm run build:edge-shared를 사용한다.
export const WORLD_BOSS_RULES = {
  eventId: 'noise-zero-local-01',
  name: 'NOISE//ZERO',
  subtitle: '거대 악플 코어',
  timeZone: 'Asia/Seoul',
  scheduleHours: [17, 18, 19, 20],
  attackEnergyCost: 10,
  slotTiers: {
    // 서버 자동딜은 0. 처치는 참가자 합산 피해와 maxHp 비교로만 결정한다.
    // 2026-08-02 긴급 조정: 17시 140억 유지, 남은 회차 160/170/190억.
    // 2026-08-03: 위 긴급 상향분까지 네 회차 전부 격파돼 180/210/240/270억으로 올린다.
    //   슬롯 간격도 10~20억에서 30억으로 벌린다.
    // 2026-08-03 재조정: 08-02 에 포인트를 과하게 지급해 전체 화력이 더 오를 것으로 보고
    //   회차 시작 전에 220/250/280/340억으로 한 번 더 올린다. 20시만 간격 60억.
    // 2026-08-03 재조정 2: 포인트 전환량을 가늠할 수 없어 앞 회차를 더 두껍게 잡는다
    //   (250/280/310/350억, 간격 30/30/40억).
    // 2026-08-03 당일 하향: 실측 결과 17시 250억은 21분 격파(적정)였으나 18시 280억이
    //   마감 1분 전 97.65% 로 실패 직전이었다. 뒤 회차를 19:280억 / 20:300억으로 낮춘다.
    //   18시와 19시가 같은 280억이 되고 20시만 소폭 높은 형태다.
    // 2026-08-03 당일 하향 2: 19시도 268.0억(95.7%)으로 실패해 20시를 280억까지 내린다.
    //   30분 회차 실측 딜이 268~273억 구간이라 250/280/280/280 계단이 된다.
    // 2026-08-04: 08-03 결과는 250억 격파 / 280억 실패 / 280억 실패 / 280억 격파(280.2억)로
    //   280억이 경계선이었다. 앞 회차를 낮춰 250/260/270/280억 10억 계단으로 만든다.
    // 2026-08-05: 08-04 는 네 회차 전부 격파(초과딜 0.03~0.08억)로 계단이 맞았다.
    //   성장분만 따라가도록 전 회차 +5억(255/265/275/285억).
    // 2026-08-11: 네 회차 모두 10억씩 상향(255/265/275/285 -> 265/275/285/295억).
    // 2026-08-12: 다시 10억씩 상향(265/275/285/295 -> 275/285/295/305억).
    // difficultyMultiplier는 표시용이며 17시 대비 HP 비율과 맞춘다.
    17: {
      title: '신호 요새', name: 'SIGNAL//BASTION', difficultyMultiplier: 1,
      maxHp: 27_500_000_000, serverDamagePerSecond: 0, clearDestructionGuardRate: 0.05,
      image: 'assets/renewal/worldboss/boss-17-signal-bastion.webp',
    },
    18: {
      title: '중계 포식자', name: 'RELAY//DEVOURER', difficultyMultiplier: 1.036,
      maxHp: 28_500_000_000, serverDamagePerSecond: 0, clearDestructionGuardRate: 0.10,
      image: 'assets/renewal/worldboss/boss-18-relay-devourer.webp',
    },
    19: {
      title: '공허 수확자', name: 'VOID//HARVESTER', difficultyMultiplier: 1.073,
      maxHp: 29_500_000_000, serverDamagePerSecond: 0, clearDestructionGuardRate: 0.15,
      image: 'assets/renewal/worldboss/boss-19-void-harvester.webp',
    },
    20: {
      title: '악의 특이점', name: 'MALICE//SINGULARITY', difficultyMultiplier: 1.109,
      maxHp: 30_500_000_000, serverDamagePerSecond: 0, clearDestructionGuardRate: 0.20,
      image: 'assets/renewal/worldboss/boss-20-malice-singularity.webp',
    },
  },
  maxHp: 27_500_000_000,
  battleDuration: 60,
  maxAttempts: 3,
  eventDurationSeconds: 60 * 60,
  raidDurationSeconds: 30 * 60,
  serverDamagePerSecond: 0,
  cardExpPerAttempt: 25,
  // 티어 추가 전 DB 제약을 확인한다: claimed_tier <= 15, reward_points <= 100000.
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
    { damage: 70_000_000, points: 50000, failurePoints: 18000, label: '7,000만' },
    { damage: 80_000_000, points: 60000, failurePoints: 21000, label: '8,000만' },
    { damage: 90_000_000, points: 70000, failurePoints: 24000, label: '9,000만' },
  ],
};
