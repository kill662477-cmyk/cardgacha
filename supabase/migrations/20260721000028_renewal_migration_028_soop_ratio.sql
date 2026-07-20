update public.gacha_s2_balance_versions set active = false where active and version <> '2026.07.21-soop-ratio';

insert into public.gacha_s2_balance_versions (version, config_hash, catalog_hash, config, active, activated_at)
values (
  '2026.07.21-soop-ratio',
  '68145476780d507bf1eb9b3cd23890c15e0894ee76b945024438e705b074067f',
  '8e7351c09b8fe082cb9d54e1884e5c409a664230b291ec7a1e18fb3d16555014',
  $balance${"balanceVersion":"2026.07.21-soop-ratio","rarities":{"F":{"multiplier":1,"color":"#89939b"},"E":{"multiplier":1.12,"color":"#58b97a"},"D":{"multiplier":1.26,"color":"#4aa8d8"},"C":{"multiplier":1.42,"color":"#7f79df"},"B":{"multiplier":1.62,"color":"#bb69e8"},"A":{"multiplier":1.86,"color":"#ef5f83"},"S":{"multiplier":2.15,"color":"#ff9b3f"},"SS":{"multiplier":2.52,"color":"#ffd449"},"SSS":{"multiplier":3,"color":"#d7ff35"},"EX":{"multiplier":0,"color":"#f7f7f2","displayOnly":true}},"archetypes":{"quick":{"label":"속공","atk":0.9,"hp":0.94,"def":0.9,"speed":1.28,"crit":0.05},"heavy":{"label":"강타","atk":1.28,"hp":1.04,"def":1,"speed":0.78,"critDamage":0.2},"combo":{"label":"연타","atk":0.96,"hp":0.96,"def":0.94,"speed":1.12,"multiHit":1.1},"area":{"label":"광역","atk":1.04,"hp":0.98,"def":0.94,"speed":0.94,"area":1.18},"boss":{"label":"보스","atk":1.08,"hp":1.03,"def":1,"speed":0.91,"bossDamage":1.28},"amplify":{"label":"증폭","atk":1.02,"hp":0.95,"def":0.92,"speed":1,"crit":0.09,"amplify":0.04},"weaken":{"label":"약화","atk":0.92,"hp":1.02,"def":1.02,"speed":1.03,"weaken":0.08},"sustain":{"label":"생존","atk":0.91,"hp":1.24,"def":1.18,"speed":0.88,"recovery":0.08}},"enhancement":{"statMultipliers":[1,1.12,1.27,1.44,1.63,1.85,2.1,2.38,2.7,3],"baseSuccessRates":[100,100,100,100,80,70,60,50,40,30],"destroyRates":[0,0,0,0,0,0,0,3,8,15],"rarityPenalties":{"F":0,"E":2,"D":4,"C":6,"B":8,"A":10,"S":12,"SS":15,"SSS":18},"expRequirements":[100,180,300,480,720,1000,1400,1900,2500,0],"plusNinePointCost":5000,"resetOnDestroy":true},"materialRules":{"F":[{"rarity":"F","count":1}],"E":[{"rarity":"F","count":3}],"D":[{"rarity":"E","count":3}],"C":[{"rarity":"D","count":3}],"B":[{"rarity":"C","count":3}],"A":[{"rarity":"B","count":3}],"S":[{"rarity":"A","count":3}],"SS":[{"rarity":"S","count":3}],"SSS":[{"rarity":"SS","count":3},{"rarity":"SSS","count":1}]},"dismantleRules":{"potionItem":"cardExpPotionLarge","keepCopies":1,"dropRates":{"F":{"potionRate":0.1,"pointsRate":0.1,"points":5},"E":{"potionRate":0.15,"pointsRate":0.15,"points":10},"D":{"potionRate":0.2,"pointsRate":0.2,"points":20},"C":{"potionRate":0.25,"pointsRate":0.25,"points":40},"B":{"potionRate":0.3,"pointsRate":0.3,"points":70},"A":{"potionRate":0.35,"pointsRate":0.35,"points":120},"S":{"potionRate":0.5,"pointsRate":0.5,"points":300},"SS":{"potionRate":0.7,"pointsRate":0.7,"points":800},"SSS":{"potionRate":0.9,"pointsRate":0.9,"points":2000}}},"packs":{"general":{"name":"일반 보급팩","price":50,"count":3,"rates":{"F":32,"E":27,"D":20,"C":12,"B":6,"A":2.856,"S":0.12,"SS":0.018,"SSS":0.006}},"elite":{"name":"정예 보급팩","price":150,"count":4,"rates":{"F":20,"E":22,"D":22,"C":16,"B":11,"A":8.478,"S":0.42,"SS":0.09,"SSS":0.012}},"premium":{"name":"프리미엄 보급팩","price":500,"count":4,"rates":{"F":9,"E":14,"D":19.5,"C":21,"B":18,"A":17.2,"S":1,"SS":0.25,"SSS":0.05}},"race":{"name":"종족 보급팩","price":100,"count":3,"rates":{"F":38,"E":30,"D":18,"C":9,"B":4,"A":0.9658,"S":0.03,"SS":0.0036,"SSS":0.0006}}},"supportPack":{"name":"작전 지원 보급팩","price":150,"tenPrice":1500,"items":{"energySmall":19,"energyMedium":11,"energyLarge":3,"enhance5":16,"enhance10":6,"destructionGuard":1,"cardExpPotion":8,"exp30m":14,"exp2h":9,"generalTicket":6,"eliteTicket":3.5,"raceTicket":2,"premiumTicket":0.5,"adventureRunReset":0.25,"quickBattleReset":0.75},"rareItems":["energyLarge","enhance10","destructionGuard","exp2h","generalTicket","eliteTicket","raceTicket","premiumTicket","adventureRunReset","quickBattleReset"],"guaranteeRates":{"energyLarge":10,"enhance10":24,"destructionGuard":3,"exp2h":28,"generalTicket":15,"eliteTicket":8,"raceTicket":5,"premiumTicket":2,"adventureRunReset":1,"quickBattleReset":4}},"supportItems":{"energySmall":{"name":"전술 배터리 S","category":"행동력","effect":"행동력 +20","energy":20},"energyMedium":{"name":"전술 배터리 M","category":"행동력","effect":"행동력 +50","energy":50},"energyLarge":{"name":"전술 배터리 L","category":"행동력","effect":"행동력 +120","energy":120},"enhance5":{"name":"강화 촉진제","category":"강화","effect":"성공률 +5%p"},"enhance10":{"name":"고순도 강화 촉진제","category":"강화","effect":"성공률 +10%p"},"destructionGuard":{"name":"파괴 차단제","category":"강화","effect":"파괴 1회 차단"},"cardExpPotion":{"name":"카드 EXP 포션","category":"경험치","effect":"선택 카드 EXP +300","cardExp":300},"cardExpPotionLarge":{"name":"농축 카드 EXP 포션","category":"경험치","effect":"선택 카드 EXP +20","cardExp":20},"exp30m":{"name":"경험 신호 증폭제","category":"경험치","effect":"카드 EXP +50% · 30분","durationMinutes":30},"exp2h":{"name":"고출력 경험 신호 증폭제","category":"경험치","effect":"카드 EXP +50% · 2시간","durationMinutes":120},"generalTicket":{"name":"일반 카드팩 교환권","category":"교환권","effect":"일반팩 1개","pack":"general"},"eliteTicket":{"name":"정예 카드팩 교환권","category":"교환권","effect":"정예팩 1개","pack":"elite"},"raceTicket":{"name":"종족 선택팩 교환권","category":"교환권","effect":"종족팩 1개","pack":"race"},"premiumTicket":{"name":"프리미엄 카드팩 교환권","category":"교환권","effect":"프리미엄팩 1개","pack":"premium"},"adventureRunReset":{"name":"모험 시작 초기화권","category":"초기화","effect":"모험 시작 횟수 3회 복구","reset":"adventureRuns"},"quickBattleReset":{"name":"빠른 전투 초기화권","category":"초기화","effect":"오늘 빠른 전투 횟수 3회 복구","reset":"quickBattle"}},"bonusDropRules":{"itemWeights":{"energySmall":24,"energyMedium":14,"energyLarge":4,"enhance5":18,"enhance10":6,"destructionGuard":1,"cardExpPotion":14,"exp30m":12,"exp2h":5,"adventureRunReset":1,"quickBattleReset":1},"packWeights":{"generalTicket":55,"eliteTicket":27,"raceTicket":15,"premiumTicket":3},"adventureTiers":[{"minClearedStages":1,"dropRate":0.18,"packShare":0.08},{"minClearedStages":10,"dropRate":0.24,"packShare":0.12},{"minClearedStages":20,"dropRate":0.3,"packShare":0.16},{"minClearedStages":30,"dropRate":0.36,"packShare":0.2},{"minClearedStages":40,"dropRate":0.43,"packShare":0.24},{"minClearedStages":50,"dropRate":0.5,"packShare":0.3}],"worldBoss":{"failed":{"dropRate":0.35,"packShare":0.15},"cleared":{"dropRate":0.6,"packShare":0.25}}},"regions":[{"id":1,"name":"끊어진 전파도시","code":"signal-city","hpBase":590000,"attackBase":3000,"bossHp":1200000,"bossAttack":4000},{"id":2,"name":"침묵한 중계기지","code":"relay-base","hpBase":1100000,"attackBase":4500,"bossHp":1820000,"bossAttack":6000},{"id":3,"name":"검게 물든 스튜디오","code":"black-studio","hpBase":1700000,"attackBase":6500,"bossHp":2800000,"bossAttack":8500},{"id":4,"name":"폭주한 데이터 요새","code":"data-fortress","hpBase":2500000,"attackBase":9000,"bossHp":4000000,"bossAttack":11000},{"id":5,"name":"악플 코어 심층부","code":"malice-core","hpBase":4200000,"attackBase":12500,"bossHp":9500000,"bossAttack":21000}],"stages":[{"id":"1-1","region":"끊어진 전파도시","regionCode":"signal-city","regionIndex":0,"stageNumber":1,"globalNumber":1,"enemyType":"crawler","enemyCount":4,"enemyHp":590000,"enemyAttack":3000,"duration":30,"rewardPoints":22,"boss":false},{"id":"1-2","region":"끊어진 전파도시","regionCode":"signal-city","regionIndex":0,"stageNumber":2,"globalNumber":2,"enemyType":"jammer","enemyCount":4,"enemyHp":637200,"enemyAttack":3090,"duration":31,"rewardPoints":26,"boss":false},{"id":"1-3","region":"끊어진 전파도시","regionCode":"signal-city","regionIndex":0,"stageNumber":3,"globalNumber":3,"enemyType":"leech","enemyCount":5,"enemyHp":688176,"enemyAttack":3183,"duration":32,"rewardPoints":30,"boss":false},{"id":"1-4","region":"끊어진 전파도시","regionCode":"signal-city","regionIndex":0,"stageNumber":4,"globalNumber":4,"enemyType":"crusher","enemyCount":5,"enemyHp":743230,"enemyAttack":3278,"duration":33,"rewardPoints":34,"boss":false},{"id":"1-5","region":"끊어진 전파도시","regionCode":"signal-city","regionIndex":0,"stageNumber":5,"globalNumber":5,"enemyType":"crawler","enemyCount":5,"enemyHp":802688,"enemyAttack":3377,"duration":34,"rewardPoints":38,"boss":false},{"id":"1-6","region":"끊어진 전파도시","regionCode":"signal-city","regionIndex":0,"stageNumber":6,"globalNumber":6,"enemyType":"jammer","enemyCount":6,"enemyHp":866904,"enemyAttack":3478,"duration":35,"rewardPoints":42,"boss":false},{"id":"1-7","region":"끊어진 전파도시","regionCode":"signal-city","regionIndex":0,"stageNumber":7,"globalNumber":7,"enemyType":"leech","enemyCount":6,"enemyHp":936256,"enemyAttack":3582,"duration":36,"rewardPoints":46,"boss":false},{"id":"1-8","region":"끊어진 전파도시","regionCode":"signal-city","regionIndex":0,"stageNumber":8,"globalNumber":8,"enemyType":"crusher","enemyCount":6,"enemyHp":1011156,"enemyAttack":3690,"duration":37,"rewardPoints":50,"boss":false},{"id":"1-9","region":"끊어진 전파도시","regionCode":"signal-city","regionIndex":0,"stageNumber":9,"globalNumber":9,"enemyType":"crawler","enemyCount":7,"enemyHp":1092049,"enemyAttack":3800,"duration":38,"rewardPoints":54,"boss":false},{"id":"1-10","region":"끊어진 전파도시","regionCode":"signal-city","regionIndex":0,"stageNumber":10,"globalNumber":10,"enemyType":"boss","enemyCount":1,"enemyHp":1200000,"enemyAttack":4000,"duration":40,"rewardPoints":58,"boss":true},{"id":"2-1","region":"침묵한 중계기지","regionCode":"relay-base","regionIndex":1,"stageNumber":1,"globalNumber":11,"enemyType":"jammer","enemyCount":4,"enemyHp":1100000,"enemyAttack":4500,"duration":32,"rewardPoints":62,"boss":false},{"id":"2-2","region":"침묵한 중계기지","regionCode":"relay-base","regionIndex":1,"stageNumber":2,"globalNumber":12,"enemyType":"leech","enemyCount":4,"enemyHp":1127500,"enemyAttack":4590,"duration":32,"rewardPoints":66,"boss":false},{"id":"2-3","region":"침묵한 중계기지","regionCode":"relay-base","regionIndex":1,"stageNumber":3,"globalNumber":13,"enemyType":"crusher","enemyCount":5,"enemyHp":1155688,"enemyAttack":4682,"duration":32,"rewardPoints":70,"boss":false},{"id":"2-4","region":"침묵한 중계기지","regionCode":"relay-base","regionIndex":1,"stageNumber":4,"globalNumber":14,"enemyType":"crawler","enemyCount":5,"enemyHp":1184580,"enemyAttack":4775,"duration":32,"rewardPoints":74,"boss":false},{"id":"2-5","region":"침묵한 중계기지","regionCode":"relay-base","regionIndex":1,"stageNumber":5,"globalNumber":15,"enemyType":"jammer","enemyCount":5,"enemyHp":1214194,"enemyAttack":4871,"duration":32,"rewardPoints":78,"boss":false},{"id":"2-6","region":"침묵한 중계기지","regionCode":"relay-base","regionIndex":1,"stageNumber":6,"globalNumber":16,"enemyType":"leech","enemyCount":6,"enemyHp":1244549,"enemyAttack":4968,"duration":32,"rewardPoints":82,"boss":false},{"id":"2-7","region":"침묵한 중계기지","regionCode":"relay-base","regionIndex":1,"stageNumber":7,"globalNumber":17,"enemyType":"crusher","enemyCount":6,"enemyHp":1275663,"enemyAttack":5068,"duration":32,"rewardPoints":86,"boss":false},{"id":"2-8","region":"침묵한 중계기지","regionCode":"relay-base","regionIndex":1,"stageNumber":8,"globalNumber":18,"enemyType":"crawler","enemyCount":6,"enemyHp":1307554,"enemyAttack":5169,"duration":32,"rewardPoints":90,"boss":false},{"id":"2-9","region":"침묵한 중계기지","regionCode":"relay-base","regionIndex":1,"stageNumber":9,"globalNumber":19,"enemyType":"jammer","enemyCount":7,"enemyHp":1340243,"enemyAttack":5272,"duration":32,"rewardPoints":94,"boss":false},{"id":"2-10","region":"침묵한 중계기지","regionCode":"relay-base","regionIndex":1,"stageNumber":10,"globalNumber":20,"enemyType":"boss","enemyCount":1,"enemyHp":1820000,"enemyAttack":6000,"duration":43,"rewardPoints":98,"boss":true},{"id":"3-1","region":"검게 물든 스튜디오","regionCode":"black-studio","regionIndex":2,"stageNumber":1,"globalNumber":21,"enemyType":"leech","enemyCount":4,"enemyHp":1700000,"enemyAttack":6500,"duration":34,"rewardPoints":102,"boss":false},{"id":"3-2","region":"검게 물든 스튜디오","regionCode":"black-studio","regionIndex":2,"stageNumber":2,"globalNumber":22,"enemyType":"crusher","enemyCount":4,"enemyHp":1742500,"enemyAttack":6630,"duration":34,"rewardPoints":106,"boss":false},{"id":"3-3","region":"검게 물든 스튜디오","regionCode":"black-studio","regionIndex":2,"stageNumber":3,"globalNumber":23,"enemyType":"crawler","enemyCount":5,"enemyHp":1786062,"enemyAttack":6763,"duration":34,"rewardPoints":110,"boss":false},{"id":"3-4","region":"검게 물든 스튜디오","regionCode":"black-studio","regionIndex":2,"stageNumber":4,"globalNumber":24,"enemyType":"jammer","enemyCount":5,"enemyHp":1830714,"enemyAttack":6898,"duration":34,"rewardPoints":114,"boss":false},{"id":"3-5","region":"검게 물든 스튜디오","regionCode":"black-studio","regionIndex":2,"stageNumber":5,"globalNumber":25,"enemyType":"leech","enemyCount":5,"enemyHp":1876482,"enemyAttack":7036,"duration":34,"rewardPoints":118,"boss":false},{"id":"3-6","region":"검게 물든 스튜디오","regionCode":"black-studio","regionIndex":2,"stageNumber":6,"globalNumber":26,"enemyType":"crusher","enemyCount":6,"enemyHp":1923394,"enemyAttack":7177,"duration":34,"rewardPoints":122,"boss":false},{"id":"3-7","region":"검게 물든 스튜디오","regionCode":"black-studio","regionIndex":2,"stageNumber":7,"globalNumber":27,"enemyType":"crawler","enemyCount":6,"enemyHp":1971479,"enemyAttack":7320,"duration":34,"rewardPoints":126,"boss":false},{"id":"3-8","region":"검게 물든 스튜디오","regionCode":"black-studio","regionIndex":2,"stageNumber":8,"globalNumber":28,"enemyType":"jammer","enemyCount":6,"enemyHp":2020766,"enemyAttack":7466,"duration":34,"rewardPoints":130,"boss":false},{"id":"3-9","region":"검게 물든 스튜디오","regionCode":"black-studio","regionIndex":2,"stageNumber":9,"globalNumber":29,"enemyType":"leech","enemyCount":7,"enemyHp":2071285,"enemyAttack":7616,"duration":34,"rewardPoints":134,"boss":false},{"id":"3-10","region":"검게 물든 스튜디오","regionCode":"black-studio","regionIndex":2,"stageNumber":10,"globalNumber":30,"enemyType":"boss","enemyCount":1,"enemyHp":2800000,"enemyAttack":8500,"duration":46,"rewardPoints":138,"boss":true},{"id":"4-1","region":"폭주한 데이터 요새","regionCode":"data-fortress","regionIndex":3,"stageNumber":1,"globalNumber":31,"enemyType":"crusher","enemyCount":4,"enemyHp":2500000,"enemyAttack":9000,"duration":36,"rewardPoints":142,"boss":false},{"id":"4-2","region":"폭주한 데이터 요새","regionCode":"data-fortress","regionIndex":3,"stageNumber":2,"globalNumber":32,"enemyType":"crawler","enemyCount":4,"enemyHp":2562500,"enemyAttack":9180,"duration":36,"rewardPoints":146,"boss":false},{"id":"4-3","region":"폭주한 데이터 요새","regionCode":"data-fortress","regionIndex":3,"stageNumber":3,"globalNumber":33,"enemyType":"jammer","enemyCount":5,"enemyHp":2626563,"enemyAttack":9364,"duration":36,"rewardPoints":150,"boss":false},{"id":"4-4","region":"폭주한 데이터 요새","regionCode":"data-fortress","regionIndex":3,"stageNumber":4,"globalNumber":34,"enemyType":"leech","enemyCount":5,"enemyHp":2692227,"enemyAttack":9551,"duration":36,"rewardPoints":154,"boss":false},{"id":"4-5","region":"폭주한 데이터 요새","regionCode":"data-fortress","regionIndex":3,"stageNumber":5,"globalNumber":35,"enemyType":"crusher","enemyCount":5,"enemyHp":2759532,"enemyAttack":9742,"duration":36,"rewardPoints":158,"boss":false},{"id":"4-6","region":"폭주한 데이터 요새","regionCode":"data-fortress","regionIndex":3,"stageNumber":6,"globalNumber":36,"enemyType":"crawler","enemyCount":6,"enemyHp":2828521,"enemyAttack":9937,"duration":36,"rewardPoints":162,"boss":false},{"id":"4-7","region":"폭주한 데이터 요새","regionCode":"data-fortress","regionIndex":3,"stageNumber":7,"globalNumber":37,"enemyType":"jammer","enemyCount":6,"enemyHp":2899234,"enemyAttack":10135,"duration":36,"rewardPoints":166,"boss":false},{"id":"4-8","region":"폭주한 데이터 요새","regionCode":"data-fortress","regionIndex":3,"stageNumber":8,"globalNumber":38,"enemyType":"leech","enemyCount":6,"enemyHp":2971714,"enemyAttack":10338,"duration":36,"rewardPoints":170,"boss":false},{"id":"4-9","region":"폭주한 데이터 요새","regionCode":"data-fortress","regionIndex":3,"stageNumber":9,"globalNumber":39,"enemyType":"crusher","enemyCount":7,"enemyHp":3046007,"enemyAttack":10545,"duration":36,"rewardPoints":174,"boss":false},{"id":"4-10","region":"폭주한 데이터 요새","regionCode":"data-fortress","regionIndex":3,"stageNumber":10,"globalNumber":40,"enemyType":"boss","enemyCount":1,"enemyHp":4000000,"enemyAttack":11000,"duration":49,"rewardPoints":178,"boss":true},{"id":"5-1","region":"악플 코어 심층부","regionCode":"malice-core","regionIndex":4,"stageNumber":1,"globalNumber":41,"enemyType":"crawler","enemyCount":4,"enemyHp":4200000,"enemyAttack":12500,"duration":38,"rewardPoints":182,"boss":false},{"id":"5-2","region":"악플 코어 심층부","regionCode":"malice-core","regionIndex":4,"stageNumber":2,"globalNumber":42,"enemyType":"jammer","enemyCount":4,"enemyHp":4305000,"enemyAttack":12750,"duration":38,"rewardPoints":186,"boss":false},{"id":"5-3","region":"악플 코어 심층부","regionCode":"malice-core","regionIndex":4,"stageNumber":3,"globalNumber":43,"enemyType":"leech","enemyCount":5,"enemyHp":4412625,"enemyAttack":13005,"duration":38,"rewardPoints":190,"boss":false},{"id":"5-4","region":"악플 코어 심층부","regionCode":"malice-core","regionIndex":4,"stageNumber":4,"globalNumber":44,"enemyType":"crusher","enemyCount":5,"enemyHp":4522941,"enemyAttack":13265,"duration":38,"rewardPoints":194,"boss":false},{"id":"5-5","region":"악플 코어 심층부","regionCode":"malice-core","regionIndex":4,"stageNumber":5,"globalNumber":45,"enemyType":"crawler","enemyCount":5,"enemyHp":4636014,"enemyAttack":13530,"duration":38,"rewardPoints":198,"boss":false},{"id":"5-6","region":"악플 코어 심층부","regionCode":"malice-core","regionIndex":4,"stageNumber":6,"globalNumber":46,"enemyType":"jammer","enemyCount":6,"enemyHp":4751914,"enemyAttack":13801,"duration":38,"rewardPoints":202,"boss":false},{"id":"5-7","region":"악플 코어 심층부","regionCode":"malice-core","regionIndex":4,"stageNumber":7,"globalNumber":47,"enemyType":"leech","enemyCount":6,"enemyHp":4870712,"enemyAttack":14077,"duration":38,"rewardPoints":206,"boss":false},{"id":"5-8","region":"악플 코어 심층부","regionCode":"malice-core","regionIndex":4,"stageNumber":8,"globalNumber":48,"enemyType":"crusher","enemyCount":6,"enemyHp":4992480,"enemyAttack":14359,"duration":38,"rewardPoints":210,"boss":false},{"id":"5-9","region":"악플 코어 심층부","regionCode":"malice-core","regionIndex":4,"stageNumber":9,"globalNumber":49,"enemyType":"crawler","enemyCount":7,"enemyHp":5117292,"enemyAttack":14646,"duration":38,"rewardPoints":214,"boss":false},{"id":"5-10","region":"악플 코어 심층부","regionCode":"malice-core","regionIndex":4,"stageNumber":10,"globalNumber":50,"enemyType":"boss","enemyCount":1,"enemyHp":9500000,"enemyAttack":21000,"duration":52,"rewardPoints":218,"boss":true}],"gameRules":{"formationSize":5,"battleTickMs":250,"playbackScale":0.22,"baseCardStats":{"atk":3600,"hp":14500,"def":620,"speed":1,"crit":0.08,"critDamage":1.5},"raceSynergy":{"3":{"atk":1.05,"hp":1.05},"5":{"atk":1.12,"hp":1.12}}},"adventureRules":{"maxRunsPerWindow":3,"runWindowMs":14400000,"runReward":{"pointsBasePerStage":20,"pointsGrowthPerStage":5.5,"maxPointsPerRun":8000,"cardExpPerClearedStage":1}},"rewardRules":{"maxStage":50,"maxActionEnergy":120,"offlineCapHours":24,"quickBattleHours":2,"quickBattleEnergy":20,"quickBattleDailyLimit":3,"energyRecoveryMinutes":6,"cardExpBasePerMinute":0.04,"cardExpPerStage":0.004},"collectionRules":{"combatBonusCap":1,"memberCompletionBonus":0.0125,"raceCompletionBonus":0.05,"rarityCompletionBonus":0.025,"overallMilestones":[0.25,0.5,0.75,1],"overallCompletionBonus":0.0375,"idlePerMilestone":0.06,"idlePerRaceCompletion":0.02},"miniGameRules":{"energyCost":10,"dailyPointCapPerGame":3000,"memory":{"basic":{"label":"4×4","pairs":8,"columns":4,"timeLimit":90,"completionReward":500},"advanced":{"label":"6×6","pairs":18,"columns":6,"timeLimit":150,"completionReward":1500}},"sumTen":{"label":"캄몬사과게임","rows":10,"columns":17,"timeLimit":120,"baseReward":40,"rewardPerScore":17,"maxReward":3000}},"worldBossRules":{"eventId":"noise-zero-local-01","name":"NOISE//ZERO","subtitle":"거대 악플 코어","timeZone":"Asia/Seoul","scheduleHours":[17,18,19,20],"maxHp":5000000000,"battleDuration":60,"maxAttempts":3,"eventDurationSeconds":3600,"raidDurationSeconds":1800,"serverDamagePerSecond":2766667,"cardExpPerAttempt":25,"rewardTiers":[{"damage":1,"points":1000,"failurePoints":250,"label":"참여"},{"damage":2000000,"points":2000,"failurePoints":500,"label":"200만"},{"damage":5000000,"points":3500,"failurePoints":1000,"label":"500만"},{"damage":10000000,"points":5500,"failurePoints":2000,"label":"1,000만"},{"damage":15000000,"points":8000,"failurePoints":3000,"label":"1,500만"},{"damage":20000000,"points":10000,"failurePoints":5000,"label":"2,000만"}]},"soopRules":{"pointsPerBalloon":5},"exDistributionRules":{"enabled":true,"status":"adventure-milestones-v1","packEligible":false,"combatEligible":false,"collectionBonusEligible":false,"milestones":[{"clearedStage":5,"cardId":"group-1"},{"clearedStage":10,"cardId":"group-2"},{"clearedStage":15,"cardId":"group-3"},{"clearedStage":20,"cardId":"group-4"},{"clearedStage":25,"cardId":"group-5"},{"clearedStage":30,"cardId":"group-6"},{"clearedStage":40,"cardId":"group-7"},{"clearedStage":50,"cardId":"group-8"}]}}$balance$::jsonb,
  true,
  now()
)
on conflict (version) do update set
  config_hash = excluded.config_hash,
  catalog_hash = excluded.catalog_hash,
  config = excluded.config,
  active = true,
  activated_at = excluded.activated_at;

insert into public.gacha_s2_card_catalog (
  card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group, balance_version
)
values
  ('arisongi-1', '아리송이', 'arisongi-1.avif', 'A', '프로토스', 'sustain', 'HR', false, '2026.07.21-soop-ratio'),
  ('arisongi-10', '아리송이', 'arisongi-10.avif', 'F', '프로토스', 'area', 'U', false, '2026.07.21-soop-ratio'),
  ('arisongi-2', '아리송이', 'arisongi-2.avif', 'C', '프로토스', 'heavy', 'RR', false, '2026.07.21-soop-ratio'),
  ('arisongi-3', '아리송이', 'arisongi-3.avif', 'E', '프로토스', 'area', 'U', false, '2026.07.21-soop-ratio'),
  ('arisongi-4', '아리송이', 'arisongi-4.jpg', 'C', '프로토스', 'sustain', 'RRR', false, '2026.07.21-soop-ratio'),
  ('arisongi-5', '아리송이', 'arisongi-5.jpeg', 'B', '프로토스', 'combo', 'AR', false, '2026.07.21-soop-ratio'),
  ('arisongi-6', '아리송이', 'arisongi-6.jpeg', 'S', '프로토스', 'sustain', 'MUR', false, '2026.07.21-soop-ratio'),
  ('arisongi-7', '아리송이', 'arisongi-7.avif', 'A', '프로토스', 'combo', 'HR', false, '2026.07.21-soop-ratio'),
  ('arisongi-8', '아리송이', 'arisongi-8.avif', 'B', '프로토스', 'heavy', 'AR', false, '2026.07.21-soop-ratio'),
  ('arisongi-9', '아리송이', 'arisongi-9.avif', 'D', '프로토스', 'combo', 'RR', false, '2026.07.21-soop-ratio'),
  ('baeseongheum-1', '배성흠', 'baeseongheum-1.avif', 'D', '저그', 'weaken', 'C', false, '2026.07.21-soop-ratio'),
  ('baeseongheum-2', '배성흠', 'baeseongheum-2.webp', 'E', '저그', 'boss', 'C', false, '2026.07.21-soop-ratio'),
  ('baeseongheum-3', '배성흠', 'baeseongheum-3.jpg', 'B', '저그', 'boss', 'SR', false, '2026.07.21-soop-ratio'),
  ('baeseongheum-4', '배성흠', 'baeseongheum-4.avif', 'F', '저그', 'quick', 'C', false, '2026.07.21-soop-ratio'),
  ('baeseongheum-5', '배성흠', 'baeseongheum-5.avif', 'S', '저그', 'combo', 'UR', false, '2026.07.21-soop-ratio'),
  ('baeseongheum-6', '배성흠', 'baeseongheum-6.avif', 'C', '저그', 'boss', 'R', false, '2026.07.21-soop-ratio'),
  ('byeonhyeonje-1', '변현제', 'byeonhyeonje-1.avif', 'SS', '프로토스', 'amplify', 'UR', false, '2026.07.21-soop-ratio'),
  ('byeonhyeonje-2', '변현제', 'byeonhyeonje-2.webp', 'A', '프로토스', 'quick', 'C', false, '2026.07.21-soop-ratio'),
  ('byeonhyeonje-3', '변현제', 'byeonhyeonje-3.jpg', 'B', '프로토스', 'amplify', 'C', false, '2026.07.21-soop-ratio'),
  ('byeonhyeonje-4', '변현제', 'byeonhyeonje-4.avif', 'SS', '프로토스', 'weaken', 'SAR', false, '2026.07.21-soop-ratio'),
  ('byeonhyeonje-5', '변현제', 'byeonhyeonje-5.avif', 'C', '프로토스', 'combo', 'C', false, '2026.07.21-soop-ratio'),
  ('byeonhyeonje-6', '변현제', 'byeonhyeonje-6.avif', 'SS', '프로토스', 'combo', 'MUR', false, '2026.07.21-soop-ratio'),
  ('chiri-1', '치리', 'chiri-1.avif', 'F', '저그', 'heavy', 'RR', false, '2026.07.21-soop-ratio'),
  ('chiri-11', '치리', 'chiri-11.png', 'B', '저그', 'heavy', 'UR', false, '2026.07.21-soop-ratio'),
  ('chiri-12', '치리', 'chiri-12.png', 'A', '저그', 'weaken', 'MUR', false, '2026.07.21-soop-ratio'),
  ('chiri-13', '치리', 'chiri-13.avif', 'D', '저그', 'boss', 'SAR', false, '2026.07.21-soop-ratio'),
  ('chiri-14', '치리', 'chiri-14.avif', 'SSS', '저그', 'heavy', 'FUR', false, '2026.07.21-soop-ratio'),
  ('chiri-16', '치리', 'chiri-16.avif', 'A', '저그', 'boss', 'MUR', false, '2026.07.21-soop-ratio'),
  ('chiri-17', '치리', 'chiri-17.avif', 'S', '저그', 'heavy', 'MUR', false, '2026.07.21-soop-ratio'),
  ('chiri-18', '치리', 'chiri-18.jpg', 'A', '저그', 'weaken', 'UR', false, '2026.07.21-soop-ratio'),
  ('chiri-3', '치리', 'chiri-3.webp', 'F', '저그', 'combo', 'RRR', false, '2026.07.21-soop-ratio'),
  ('chiri-4', '치리', 'chiri-4.avif', 'D', '저그', 'sustain', 'SR', false, '2026.07.21-soop-ratio'),
  ('chiri-5', '치리', 'chiri-5.avif', 'D', '저그', 'quick', 'SR', false, '2026.07.21-soop-ratio'),
  ('chiri-6', '치리', 'chiri-6.avif', 'B', '저그', 'quick', 'SAR', false, '2026.07.21-soop-ratio'),
  ('chiri-8', '치리', 'chiri-8.avif', 'E', '저그', 'combo', 'HR', false, '2026.07.21-soop-ratio'),
  ('group-1', '단체사진', 'group-1.avif', 'EX', 'EX', null, 'FUR', true, '2026.07.21-soop-ratio'),
  ('group-2', '단체사진', 'group-2.avif', 'EX', 'EX', null, 'MUR', true, '2026.07.21-soop-ratio'),
  ('group-3', '단체사진', 'group-3.avif', 'EX', 'EX', null, 'MUR', true, '2026.07.21-soop-ratio'),
  ('group-4', '단체사진', 'group-4.avif', 'EX', 'EX', null, 'UR', true, '2026.07.21-soop-ratio'),
  ('group-5', '단체사진', 'group-5.avif', 'EX', 'EX', null, 'UR', true, '2026.07.21-soop-ratio'),
  ('group-6', '단체사진', 'group-6.avif', 'EX', 'EX', null, 'SAR', true, '2026.07.21-soop-ratio'),
  ('group-7', '단체사진', 'group-7.avif', 'EX', 'EX', null, 'SAR', true, '2026.07.21-soop-ratio'),
  ('group-8', '단체사진', 'group-8.avif', 'EX', 'EX', null, 'SR', true, '2026.07.21-soop-ratio'),
  ('haetsal-1', '햇살', 'haetsal-1.avif', 'F', '테란', 'area', 'U', false, '2026.07.21-soop-ratio'),
  ('haetsal-10', '햇살', 'haetsal-10.avif', 'F', '테란', 'sustain', 'C', false, '2026.07.21-soop-ratio'),
  ('haetsal-11', '햇살', 'haetsal-11.avif', 'S', '테란', 'amplify', 'HR', false, '2026.07.21-soop-ratio'),
  ('haetsal-12', '햇살', 'haetsal-12.jpeg', 'SSS', '테란', 'weaken', 'FUR', false, '2026.07.21-soop-ratio'),
  ('haetsal-2', '햇살', 'haetsal-2.jpeg', 'B', '테란', 'weaken', 'AR', false, '2026.07.21-soop-ratio'),
  ('haetsal-3', '햇살', 'haetsal-3.jpg', 'D', '테란', 'heavy', 'AR', false, '2026.07.21-soop-ratio'),
  ('haetsal-4', '햇살', 'haetsal-4.jpg', 'D', '테란', 'combo', 'AR', false, '2026.07.21-soop-ratio'),
  ('haetsal-5', '햇살', 'haetsal-5.avif', 'S', '테란', 'weaken', 'MUR', false, '2026.07.21-soop-ratio'),
  ('haetsal-6', '햇살', 'haetsal-6.jpeg', 'E', '테란', 'area', 'R', false, '2026.07.21-soop-ratio'),
  ('haetsal-7', '햇살', 'haetsal-7-v2.jpeg', 'A', '테란', 'quick', 'SAR', false, '2026.07.21-soop-ratio'),
  ('haetsal-8', '햇살', 'haetsal-8.jpeg', 'B', '테란', 'area', 'CHR', false, '2026.07.21-soop-ratio'),
  ('haetsal-9', '햇살', 'haetsal-9.avif', 'D', '테란', 'amplify', 'RRR', false, '2026.07.21-soop-ratio'),
  ('imjoy-1', '임조이', 'imjoy-1.avif', 'B', '저그', 'sustain', 'HR', false, '2026.07.21-soop-ratio'),
  ('imjoy-10', '임조이', 'imjoy-10.avif', 'E', '저그', 'quick', 'RRR', false, '2026.07.21-soop-ratio'),
  ('imjoy-11', '임조이', 'imjoy-11.avif', 'C', '저그', 'amplify', 'CHR', false, '2026.07.21-soop-ratio'),
  ('imjoy-12', '임조이', 'imjoy-12.png', 'SSS', '저그', 'boss', 'FUR', false, '2026.07.21-soop-ratio'),
  ('imjoy-2', '임조이', 'imjoy-2.avif', 'D', '저그', 'area', 'RRR', false, '2026.07.21-soop-ratio'),
  ('imjoy-3', '임조이', 'imjoy-3.avif', 'C', '저그', 'area', 'CHR', false, '2026.07.21-soop-ratio'),
  ('imjoy-4', '임조이', 'imjoy-4.avif', 'SS', '저그', 'sustain', 'MUR', false, '2026.07.21-soop-ratio'),
  ('imjoy-5', '임조이', 'imjoy-5.avif', 'A', '저그', 'heavy', 'UR', false, '2026.07.21-soop-ratio'),
  ('imjoy-6', '임조이', 'imjoy-6.avif', 'B', '저그', 'sustain', 'HR', false, '2026.07.21-soop-ratio'),
  ('imjoy-7', '임조이', 'imjoy-7.jpg', 'F', '저그', 'combo', 'R', false, '2026.07.21-soop-ratio'),
  ('imjoy-8', '임조이', 'imjoy-8.jpeg', 'F', '저그', 'area', 'R', false, '2026.07.21-soop-ratio'),
  ('imjoy-9', '임조이', 'imjoy-9.avif', 'S', '저그', 'area', 'SAR', false, '2026.07.21-soop-ratio'),
  ('jidongwon-1', '지동원', 'jidongwon-1.avif', 'S', '테란', 'combo', 'SR', false, '2026.07.21-soop-ratio'),
  ('jidongwon-2', '지동원', 'jidongwon-2.webp', 'D', '테란', 'boss', 'C', false, '2026.07.21-soop-ratio'),
  ('jidongwon-3', '지동원', 'jidongwon-3.webp', 'E', '테란', 'amplify', 'C', false, '2026.07.21-soop-ratio'),
  ('jidongwon-4', '지동원', 'jidongwon-4.avif', 'E', '테란', 'weaken', 'C', false, '2026.07.21-soop-ratio'),
  ('jidongwon-5', '지동원', 'jidongwon-5.avif', 'B', '테란', 'combo', 'RRR', false, '2026.07.21-soop-ratio'),
  ('jidongwon-6', '지동원', 'jidongwon-6.avif', 'F', '테란', 'boss', 'C', false, '2026.07.21-soop-ratio'),
  ('jidongwon-7', '지동원', 'jidongwon-7.avif', 'C', '테란', 'quick', 'RRR', false, '2026.07.21-soop-ratio'),
  ('jidudu-1', '지두두', 'jidudu-1.jpg', 'SSS', '테란', 'quick', 'FUR', false, '2026.07.21-soop-ratio'),
  ('jidudu-10', '지두두', 'jidudu-10.avif', 'A', '테란', 'area', 'SR', false, '2026.07.21-soop-ratio'),
  ('jidudu-12', '지두두', 'jidudu-12.avif', 'E', '테란', 'heavy', 'U', false, '2026.07.21-soop-ratio'),
  ('jidudu-13', '지두두', 'jidudu-13.jpg', 'SS', '테란', 'heavy', 'MUR', false, '2026.07.21-soop-ratio'),
  ('jidudu-2', '지두두', 'jidudu-2.avif', 'S', '테란', 'area', 'SAR', false, '2026.07.21-soop-ratio'),
  ('jidudu-3', '지두두', 'jidudu-3.webp', 'SS', '테란', 'quick', 'UR', false, '2026.07.21-soop-ratio'),
  ('jidudu-4', '지두두', 'jidudu-4.avif', 'S', '테란', 'boss', 'SAR', false, '2026.07.21-soop-ratio'),
  ('jidudu-5', '지두두', 'jidudu-5.jpg', 'A', '테란', 'combo', 'SR', false, '2026.07.21-soop-ratio'),
  ('jidudu-6', '지두두', 'jidudu-6.jpg', 'D', '테란', 'amplify', 'RRR', false, '2026.07.21-soop-ratio'),
  ('jidudu-7', '지두두', 'jidudu-7.jpg', 'S', '테란', 'amplify', 'UR', false, '2026.07.21-soop-ratio'),
  ('jidudu-8', '지두두', 'jidudu-8.png', 'C', '테란', 'weaken', 'HR', false, '2026.07.21-soop-ratio'),
  ('jidudu-9', '지두두', 'jidudu-9.avif', 'SS', '테란', 'heavy', 'MUR', false, '2026.07.21-soop-ratio'),
  ('jjiking-1', '찌킹', 'jjiking-1.jpg', 'D', '저그', 'weaken', 'RR', false, '2026.07.21-soop-ratio'),
  ('jjiking-10', '찌킹', 'jjiking-10.avif', 'F', '저그', 'amplify', 'R', false, '2026.07.21-soop-ratio'),
  ('jjiking-11', '찌킹', 'jjiking-11.avif', 'F', '저그', 'weaken', 'C', false, '2026.07.21-soop-ratio'),
  ('jjiking-12', '찌킹', 'jjiking-12.jpg', 'SSS', '저그', 'sustain', 'FUR', false, '2026.07.21-soop-ratio'),
  ('jjiking-13', '찌킹', 'jjiking-13.jpg', 'SS', '저그', 'area', 'MUR', false, '2026.07.21-soop-ratio'),
  ('jjiking-2', '찌킹', 'jjiking-2.webp', 'E', '저그', 'sustain', 'RR', false, '2026.07.21-soop-ratio'),
  ('jjiking-3', '찌킹', 'jjiking-3.jpg', 'E', '저그', 'boss', 'R', false, '2026.07.21-soop-ratio'),
  ('jjiking-4', '찌킹', 'jjiking-4.jpg', 'S', '저그', 'quick', 'MUR', false, '2026.07.21-soop-ratio'),
  ('jjiking-5', '찌킹', 'jjiking-5.jpg', 'C', '저그', 'quick', 'HR', false, '2026.07.21-soop-ratio'),
  ('jjiking-6', '찌킹', 'jjiking-6.png', 'A', '저그', 'heavy', 'SR', false, '2026.07.21-soop-ratio'),
  ('jjiking-7', '찌킹', 'jjiking-7.avif', 'C', '저그', 'sustain', 'HR', false, '2026.07.21-soop-ratio'),
  ('jjiking-8', '찌킹', 'jjiking-8.avif', 'D', '저그', 'area', 'CHR', false, '2026.07.21-soop-ratio'),
  ('jjiking-9', '찌킹', 'jjiking-9.avif', 'E', '저그', 'combo', 'RR', false, '2026.07.21-soop-ratio'),
  ('juharang-1', '주하랑', 'juharang-1.avif', 'F', '프로토스', 'boss', 'U', false, '2026.07.21-soop-ratio'),
  ('juharang-10', '주하랑', 'juharang-10.avif', 'S', '프로토스', 'boss', 'UR', false, '2026.07.21-soop-ratio'),
  ('juharang-11', '주하랑', 'juharang-11.avif', 'C', '프로토스', 'weaken', 'AR', false, '2026.07.21-soop-ratio'),
  ('juharang-12', '주하랑', 'juharang-12.webp', 'SS', '프로토스', 'quick', 'MUR', false, '2026.07.21-soop-ratio'),
  ('juharang-2', '주하랑', 'juharang-2.avif', 'SS', '프로토스', 'heavy', 'MUR', false, '2026.07.21-soop-ratio'),
  ('juharang-3', '주하랑', 'juharang-3.webp', 'E', '프로토스', 'quick', 'RR', false, '2026.07.21-soop-ratio'),
  ('juharang-4', '주하랑', 'juharang-4.avif', 'B', '프로토스', 'quick', 'SR', false, '2026.07.21-soop-ratio'),
  ('juharang-6', '주하랑', 'juharang-6.webp', 'E', '프로토스', 'heavy', 'RRR', false, '2026.07.21-soop-ratio'),
  ('juharang-7', '주하랑', 'juharang-7.png', 'D', '프로토스', 'sustain', 'SR', false, '2026.07.21-soop-ratio'),
  ('juharang-8', '주하랑', 'juharang-8.png', 'C', '프로토스', 'boss', 'SAR', false, '2026.07.21-soop-ratio'),
  ('juharang-9', '주하랑', 'juharang-9.png', 'B', '프로토스', 'heavy', 'UR', false, '2026.07.21-soop-ratio'),
  ('kimmincheol-1', '김민철', 'kimmincheol-1.avif', 'B', '저그', 'combo', 'C', false, '2026.07.21-soop-ratio'),
  ('kimmincheol-2', '김민철', 'kimmincheol-2.avif', 'A', '저그', 'area', 'SAR', false, '2026.07.21-soop-ratio'),
  ('kimmincheol-3', '김민철', 'kimmincheol-3.webp', 'SS', '저그', 'combo', 'UR', false, '2026.07.21-soop-ratio'),
  ('kimmincheol-4', '김민철', 'kimmincheol-4.avif', 'C', '저그', 'amplify', 'C', false, '2026.07.21-soop-ratio'),
  ('kimmincheol-5', '김민철', 'kimmincheol-5.avif', 'SS', '저그', 'quick', 'MUR', false, '2026.07.21-soop-ratio'),
  ('kimmincheol-6', '김민철', 'kimmincheol-6.avif', 'SS', '저그', 'boss', 'MUR', false, '2026.07.21-soop-ratio'),
  ('kimmincheol-7', '김민철', 'kimmincheol-7.avif', 'SSS', '저그', 'sustain', 'FUR', false, '2026.07.21-soop-ratio'),
  ('kimyunhwan-1', '김윤환', 'kimyunhwan-1.avif', 'SS', '저그', 'area', 'MUR', false, '2026.07.21-soop-ratio'),
  ('kimyunhwan-2', '김윤환', 'kimyunhwan-2.webp', 'SSS', '저그', 'heavy', 'FUR', false, '2026.07.21-soop-ratio'),
  ('kimyunhwan-3', '김윤환', 'kimyunhwan-3.avif', 'SS', '저그', 'boss', 'MUR', false, '2026.07.21-soop-ratio'),
  ('kimyunhwan-4', '김윤환', 'kimyunhwan-4.avif', 'SSS', '저그', 'combo', 'FUR', false, '2026.07.21-soop-ratio'),
  ('kimyunhwan-5', '김윤환', 'kimyunhwan-5.avif', 'SS', '저그', 'amplify', 'MUR', false, '2026.07.21-soop-ratio'),
  ('kimyunhwan-6', '김윤환', 'kimyunhwan-6.avif', 'SS', '저그', 'sustain', 'UR', false, '2026.07.21-soop-ratio'),
  ('kimyunhwan-7', '김윤환', 'kimyunhwan-7.avif', 'SS', '저그', 'amplify', 'MUR', false, '2026.07.21-soop-ratio'),
  ('meonjin-1', '먼진', 'meonjin-1.avif', 'D', '저그', 'quick', 'R', false, '2026.07.21-soop-ratio'),
  ('meonjin-10', '먼진', 'meonjin-10.avif', 'E', '저그', 'weaken', 'R', false, '2026.07.21-soop-ratio'),
  ('meonjin-11', '먼진', 'meonjin-11.avif', 'F', '저그', 'heavy', 'U', false, '2026.07.21-soop-ratio'),
  ('meonjin-12', '먼진', 'meonjin-12.png', 'SSS', '저그', 'amplify', 'FUR', false, '2026.07.21-soop-ratio'),
  ('meonjin-13', '먼진', 'meonjin-13.jpeg', 'SS', '저그', 'weaken', 'MUR', false, '2026.07.21-soop-ratio'),
  ('meonjin-14', '먼진', 'meonjin-14.jpeg', 'S', '저그', 'quick', 'UR', false, '2026.07.21-soop-ratio'),
  ('meonjin-2', '먼진', 'meonjin-2.avif', 'F', '저그', 'amplify', 'U', false, '2026.07.21-soop-ratio'),
  ('meonjin-3', '먼진', 'meonjin-3.avif', 'D', '저그', 'heavy', 'RR', false, '2026.07.21-soop-ratio'),
  ('meonjin-4', '먼진', 'meonjin-4.avif', 'A', '저그', 'boss', 'SR', false, '2026.07.21-soop-ratio'),
  ('meonjin-5', '먼진', 'meonjin-5.avif', 'B', '저그', 'area', 'AR', false, '2026.07.21-soop-ratio'),
  ('meonjin-6', '먼진', 'meonjin-6.avif', 'A', '저그', 'area', 'SR', false, '2026.07.21-soop-ratio'),
  ('meonjin-7', '먼진', 'meonjin-7.png', 'S', '저그', 'boss', 'MUR', false, '2026.07.21-soop-ratio'),
  ('meonjin-8', '먼진', 'meonjin-8.avif', 'C', '저그', 'area', 'AR', false, '2026.07.21-soop-ratio'),
  ('meonjin-9', '먼진', 'meonjin-9.avif', 'B', '저그', 'weaken', 'CHR', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-1', '남덕선', 'namdeokseon-1.avif', 'E', '저그', 'combo', 'R', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-10', '남덕선', 'namdeokseon-10.avif', 'C', '저그', 'combo', 'SR', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-11', '남덕선', 'namdeokseon-11.avif', 'F', '저그', 'sustain', 'R', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-12', '남덕선', 'namdeokseon-12.avif', 'SSS', '저그', 'combo', 'FUR', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-2', '남덕선', 'namdeokseon-2.avif', 'D', '저그', 'combo', 'AR', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-3', '남덕선', 'namdeokseon-3.avif', 'F', '저그', 'weaken', 'C', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-4', '남덕선', 'namdeokseon-4.avif', 'C', '저그', 'weaken', 'CHR', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-5', '남덕선', 'namdeokseon-5.avif', 'E', '저그', 'area', 'R', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-6', '남덕선', 'namdeokseon-6.avif', 'E', '저그', 'boss', 'U', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-7', '남덕선', 'namdeokseon-7.avif', 'A', '저그', 'combo', 'MUR', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-8', '남덕선', 'namdeokseon-8.avif', 'D', '저그', 'sustain', 'RRR', false, '2026.07.21-soop-ratio'),
  ('namdeokseon-9', '남덕선', 'namdeokseon-9.avif', 'F', '저그', 'weaken', 'C', false, '2026.07.21-soop-ratio'),
  ('nangni-1', '낭니', 'nangni-1.avif', 'B', '저그', 'boss', 'CHR', false, '2026.07.21-soop-ratio'),
  ('nangni-10', '낭니', 'nangni-10.avif', 'D', '저그', 'quick', 'RR', false, '2026.07.21-soop-ratio'),
  ('nangni-11', '낭니', 'nangni-11.avif', 'B', '저그', 'amplify', 'HR', false, '2026.07.21-soop-ratio'),
  ('nangni-2', '낭니', 'nangni-2.avif', 'A', '저그', 'amplify', 'SR', false, '2026.07.21-soop-ratio'),
  ('nangni-3', '낭니', 'nangni-3.jpeg', 'C', '저그', 'sustain', 'RRR', false, '2026.07.21-soop-ratio'),
  ('nangni-4', '낭니', 'nangni-4.jpeg', 'A', '저그', 'weaken', 'SAR', false, '2026.07.21-soop-ratio'),
  ('nangni-5', '낭니', 'nangni-5.jpeg', 'C', '저그', 'quick', 'RR', false, '2026.07.21-soop-ratio'),
  ('nangni-6', '낭니', 'nangni-6.avif', 'S', '저그', 'area', 'MUR', false, '2026.07.21-soop-ratio'),
  ('nangni-7', '낭니', 'nangni-7.jpeg', 'E', '저그', 'amplify', 'R', false, '2026.07.21-soop-ratio'),
  ('nangni-8', '낭니', 'nangni-8.avif', 'SSS', '저그', 'boss', 'FUR', false, '2026.07.21-soop-ratio'),
  ('nangni-9', '낭니', 'nangni-9.avif', 'F', '저그', 'quick', 'U', false, '2026.07.21-soop-ratio'),
  ('parkjuno-1', '박준오', 'parkjuno-1.webp', 'C', '저그', 'heavy', 'U', false, '2026.07.21-soop-ratio'),
  ('parkjuno-2', '박준오', 'parkjuno-2.jpg', 'B', '저그', 'amplify', 'SR', false, '2026.07.21-soop-ratio'),
  ('parkjuno-3', '박준오', 'parkjuno-3.avif', 'F', '저그', 'sustain', 'C', false, '2026.07.21-soop-ratio'),
  ('parkjuno-4', '박준오', 'parkjuno-4.avif', 'E', '저그', 'amplify', 'U', false, '2026.07.21-soop-ratio'),
  ('parkjuno-5', '박준오', 'parkjuno-5.avif', 'S', '저그', 'weaken', 'SAR', false, '2026.07.21-soop-ratio'),
  ('parksubeom-1', '박수범', 'parksubeom-1.avif', 'C', '프로토스', 'combo', 'C', false, '2026.07.21-soop-ratio'),
  ('parksubeom-2', '박수범', 'parksubeom-2.jpg', 'E', '프로토스', 'weaken', 'C', false, '2026.07.21-soop-ratio'),
  ('parksubeom-3', '박수범', 'parksubeom-3.webp', 'A', '프로토스', 'sustain', 'U', false, '2026.07.21-soop-ratio'),
  ('parksubeom-4', '박수범', 'parksubeom-4.avif', 'F', '프로토스', 'quick', 'C', false, '2026.07.21-soop-ratio'),
  ('parksubeom-5', '박수범', 'parksubeom-5.avif', 'S', '프로토스', 'weaken', 'SR', false, '2026.07.21-soop-ratio'),
  ('sate-1', '사테', 'sate-1.avif', 'F', '테란', 'heavy', 'C', false, '2026.07.21-soop-ratio'),
  ('sate-2', '사테', 'sate-2.avif', 'C', '테란', 'area', 'U', false, '2026.07.21-soop-ratio'),
  ('sate-3', '사테', 'sate-3.avif', 'A', '테란', 'quick', 'SR', false, '2026.07.21-soop-ratio'),
  ('sate-4', '사테', 'sate-4.avif', 'E', '테란', 'sustain', 'U', false, '2026.07.21-soop-ratio'),
  ('sojuyang-10', '소주양', 'sojuyang-10.avif', 'B', '테란', 'quick', 'SR', false, '2026.07.21-soop-ratio'),
  ('sojuyang-13', '소주양', 'sojuyang-13.avif', 'SSS', '테란', 'quick', 'FUR', false, '2026.07.21-soop-ratio'),
  ('sojuyang-14', '소주양', 'sojuyang-14.jpg', 'SS', '테란', 'sustain', 'MUR', false, '2026.07.21-soop-ratio'),
  ('sojuyang-15', '소주양', 'sojuyang-15.jpg', 'A', '테란', 'amplify', 'UR', false, '2026.07.21-soop-ratio'),
  ('sojuyang-2', '소주양', 'sojuyang-2.avif', 'E', '테란', 'quick', 'RR', false, '2026.07.21-soop-ratio'),
  ('sojuyang-3', '소주양', 'sojuyang-3.avif', 'C', '테란', 'boss', 'CHR', false, '2026.07.21-soop-ratio'),
  ('sojuyang-4', '소주양', 'sojuyang-4.avif', 'S', '테란', 'sustain', 'SR', false, '2026.07.21-soop-ratio'),
  ('sojuyang-6', '소주양', 'sojuyang-6.jpeg', 'S', '테란', 'heavy', 'SR', false, '2026.07.21-soop-ratio'),
  ('sojuyang-7', '소주양', 'sojuyang-7.jpeg', 'D', '테란', 'weaken', 'AR', false, '2026.07.21-soop-ratio'),
  ('sojuyang-8', '소주양', 'sojuyang-8.png', 'F', '테란', 'boss', 'R', false, '2026.07.21-soop-ratio'),
  ('sojuyang-9', '소주양', 'sojuyang-9.avif', 'D', '테란', 'heavy', 'CHR', false, '2026.07.21-soop-ratio'),
  ('tomato-1', '토마토', 'tomato-1.avif', 'SS', '프로토스', 'weaken', 'MUR', false, '2026.07.21-soop-ratio'),
  ('tomato-10', '토마토', 'tomato-10.avif', 'A', '프로토스', 'sustain', 'CHR', false, '2026.07.21-soop-ratio'),
  ('tomato-11', '토마토', 'tomato-11.avif', 'SSS', '프로토스', 'amplify', 'FUR', false, '2026.07.21-soop-ratio'),
  ('tomato-12', '토마토', 'tomato-12.avif', 'B', '프로토스', 'area', 'RR', false, '2026.07.21-soop-ratio'),
  ('tomato-13', '토마토', 'tomato-13.avif', 'SS', '프로토스', 'area', 'UR', false, '2026.07.21-soop-ratio'),
  ('tomato-14', '토마토', 'tomato-14.png', 'SS', '프로토스', 'combo', 'MUR', false, '2026.07.21-soop-ratio'),
  ('tomato-2', '토마토', 'tomato-2.webp', 'S', '프로토스', 'quick', 'SAR', false, '2026.07.21-soop-ratio'),
  ('tomato-3', '토마토', 'tomato-3.avif', 'A', '프로토스', 'heavy', 'RRR', false, '2026.07.21-soop-ratio'),
  ('tomato-4', '토마토', 'tomato-4.webp', 'D', '프로토스', 'area', 'U', false, '2026.07.21-soop-ratio'),
  ('tomato-5', '토마토', 'tomato-5.jpeg', 'S', '프로토스', 'heavy', 'HR', false, '2026.07.21-soop-ratio'),
  ('tomato-6', '토마토', 'tomato-6.avif', 'SSS', '프로토스', 'area', 'FUR', false, '2026.07.21-soop-ratio'),
  ('tomato-7', '토마토', 'tomato-7.avif', 'E', '프로토스', 'heavy', 'C', false, '2026.07.21-soop-ratio'),
  ('tomato-8', '토마토', 'tomato-8.avif', 'B', '프로토스', 'weaken', 'R', false, '2026.07.21-soop-ratio'),
  ('tomato-9', '토마토', 'tomato-9.png', 'S', '프로토스', 'amplify', 'CHR', false, '2026.07.21-soop-ratio'),
  ('vitaming-1', '비타밍', 'vitaming-1.avif', 'D', '테란', 'boss', 'RRR', false, '2026.07.21-soop-ratio'),
  ('vitaming-10', '비타밍', 'vitaming-10.avif', 'B', '테란', 'sustain', 'SAR', false, '2026.07.21-soop-ratio'),
  ('vitaming-11', '비타밍', 'vitaming-11.avif', 'E', '테란', 'sustain', 'RRR', false, '2026.07.21-soop-ratio'),
  ('vitaming-12', '비타밍', 'vitaming-12.avif', 'F', '테란', 'combo', 'C', false, '2026.07.21-soop-ratio'),
  ('vitaming-13', '비타밍', 'vitaming-13.avif', 'S', '테란', 'sustain', 'UR', false, '2026.07.21-soop-ratio'),
  ('vitaming-14', '비타밍', 'vitaming-14.jpeg', 'SSS', '테란', 'area', 'FUR', false, '2026.07.21-soop-ratio'),
  ('vitaming-2', '비타밍', 'vitaming-2.avif', 'S', '테란', 'combo', 'MUR', false, '2026.07.21-soop-ratio'),
  ('vitaming-3', '비타밍', 'vitaming-3.avif', 'D', '테란', 'amplify', 'AR', false, '2026.07.21-soop-ratio'),
  ('vitaming-4', '비타밍', 'vitaming-4.png', 'C', '테란', 'amplify', 'HR', false, '2026.07.21-soop-ratio'),
  ('vitaming-5', '비타밍', 'vitaming-5.png', 'A', '테란', 'boss', 'SAR', false, '2026.07.21-soop-ratio'),
  ('vitaming-6', '비타밍', 'vitaming-6.webp', 'A', '테란', 'amplify', 'SAR', false, '2026.07.21-soop-ratio'),
  ('vitaming-7', '비타밍', 'vitaming-7.png', 'F', '테란', 'amplify', 'R', false, '2026.07.21-soop-ratio'),
  ('vitaming-8', '비타밍', 'vitaming-8.png', 'B', '테란', 'boss', 'SR', false, '2026.07.21-soop-ratio'),
  ('vitaming-9', '비타밍', 'vitaming-9.png', 'C', '테란', 'heavy', 'SR', false, '2026.07.21-soop-ratio')
on conflict (card_id) do update set
  member = excluded.member,
  asset_file = excluded.asset_file,
  rarity = excluded.rarity,
  race = excluded.race,
  archetype = excluded.archetype,
  source_rarity = excluded.source_rarity,
  is_group = excluded.is_group,
  balance_version = excluded.balance_version,
  updated_at = now();

do $$
declare
  v_total integer;
  v_config_hash text;
  v_catalog_hash text;
begin
  select count(*) into v_total from public.gacha_s2_card_catalog;
  if v_total <> 214 then raise exception 'Season 2 catalog must contain exactly 214 cards, found %', v_total; end if;
  if (select count(*) from public.gacha_s2_card_catalog where rarity = 'EX') <> 8 then
    raise exception 'Season 2 catalog must contain exactly 8 EX cards';
  end if;
  if exists (
    select 1 from public.gacha_s2_card_catalog
    where rarity <> 'EX'
    group by rarity
    having count(distinct archetype) <> 8
  ) then
    raise exception 'every combat rarity must contain all 8 archetypes';
  end if;
  select config_hash, catalog_hash into v_config_hash, v_catalog_hash
  from public.gacha_s2_balance_versions
  where version = '2026.07.21-soop-ratio' and active;
  if v_config_hash is distinct from '68145476780d507bf1eb9b3cd23890c15e0894ee76b945024438e705b074067f' then raise exception 'balance config hash mismatch'; end if;
  if v_catalog_hash is distinct from '8e7351c09b8fe082cb9d54e1884e5c409a664230b291ec7a1e18fb3d16555014' then raise exception 'catalog hash mismatch'; end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'gacha_s2_player_cards_catalog_fk'
      and conrelid = 'public.gacha_s2_player_cards'::regclass
  ) then
    alter table public.gacha_s2_player_cards
      add constraint gacha_s2_player_cards_catalog_fk
      foreign key (card_id) references public.gacha_s2_card_catalog(card_id);
  end if;
end;
$$;

revoke all on table public.gacha_s2_balance_versions from public, anon, authenticated;
revoke all on table public.gacha_s2_card_catalog from public, anon, authenticated;

commit;
