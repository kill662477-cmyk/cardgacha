import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { ARENA_RULES, GAME_RULES } from '../src/renewal/config.js';
import {
  applyArenaRating,
  arenaExpectedScore,
  arenaRatingDelta,
  arenaSeasonReset,
  arenaTierBadgeMarkup,
  arenaTierBadgeSrc,
  arenaTierFor,
  arenaWeeklyReward,
  formationAsStage,
  resolveArenaMatch,
} from '../src/renewal/arena.js';

const cards = JSON.parse(await readFile(new URL('../data/renewal-cards.json', import.meta.url), 'utf8'));
const pool = cards.cards ?? cards;
const byArchetype = (archetype, rarity) => pool.find((card) => card.archetype === archetype && card.rarity === rarity)
  ?? pool.find((card) => card.archetype === archetype);
const deck = (archetypes, rarity, enhancement) => archetypes.map((archetype) => ({
  ...byArchetype(archetype, rarity),
  enhancement,
}));

// --- 티어 ---
assert.equal(ARENA_RULES.startRating, 1000);
assert.equal(arenaTierFor(ARENA_RULES.startRating).key, 'iron', '시작 점수는 아이언이어야 한다');
assert.equal(arenaTierFor(ARENA_RULES.minRating).key, 'iron', '하한도 아이언 안이어야 한다');
// 구간 경계는 딱 떨어져야 한다.
for (const tier of ARENA_RULES.tiers) {
  assert.equal(arenaTierFor(tier.minRating).key, tier.key, `${tier.label} 진입 점수가 어긋난다`);
  if (tier.minRating > 0) {
    assert.notEqual(arenaTierFor(tier.minRating - 1).key, tier.key, `${tier.label} 바로 아래는 하위 티어여야 한다`);
  }
}
// minRating 은 오름차순이어야 한다. 뒤섞이면 티어 판정이 조용히 틀린다.
const cuts = ARENA_RULES.tiers.map((tier) => tier.minRating);
assert.deepEqual(cuts, [...cuts].sort((left, right) => left - right), '티어 컷은 오름차순이어야 한다');

// 챌린저는 점수만으로는 못 된다. 그랜드마스터 점수 이상 + 상위 N등이어야 한다.
const gm = ARENA_RULES.tiers[ARENA_RULES.tiers.length - 1];
assert.equal(gm.key, 'grandmaster');
assert.equal(arenaTierFor(gm.minRating + 500).key, 'grandmaster', '등수를 모르면 챌린저가 아니다');
assert.equal(arenaTierFor(gm.minRating, 1).key, 'challenger');
assert.equal(arenaTierFor(gm.minRating, ARENA_RULES.challengerSlots).key, 'challenger');
assert.equal(
  arenaTierFor(gm.minRating, ARENA_RULES.challengerSlots + 1).key,
  'grandmaster',
  '정원을 넘은 등수는 챌린저가 아니다',
);
// 1등이어도 그랜드마스터 점수에 못 미치면 챌린저가 아니다.
assert.equal(arenaTierFor(gm.minRating - 1, 1).key, 'master');

// --- 티어 뱃지 ---
// 뱃지는 scripts/build-arena-badges.mjs 가 구운 SVG 파일이다.
// 색은 설정에서만 오게 한다. 여기가 비면 뱃지가 전부 회색으로 구워진다.
const badgeDir = new URL('../assets/renewal/arena/', import.meta.url);
for (const tier of [...ARENA_RULES.tiers, ARENA_RULES.challengerTier]) {
  assert.match(tier.color, /^#[0-9a-f]{6}$/i, `${tier.label} color 가 없다`);
  assert.match(tier.accent, /^#[0-9a-f]{6}$/i, `${tier.label} accent 가 없다`);

  // 파일이 실제로 있어야 한다. 없으면 화면에 깨진 이미지가 뜬다.
  const svg = await readFile(new URL(`${tier.key}.svg`, badgeDir), 'utf8');
  assert.ok(svg.includes('<svg'), `${tier.key}.svg 가 SVG 가 아니다`);
  assert.ok(svg.includes(tier.color), `${tier.key}.svg 에 티어 색이 안 구워졌다`);
  assert.ok(svg.includes(`aria-label="${tier.label}"`), `${tier.key}.svg 에 라벨이 없다`);
  // gradient id 가 겹치면 한 화면에 여러 뱃지를 그릴 때 색이 서로 덮인다.
  assert.ok(svg.includes(`plate-${tier.key}`), `${tier.key}.svg gradient id 가 티어별로 갈리지 않는다`);

  const markup = arenaTierBadgeMarkup(tier, 40);
  assert.ok(markup.startsWith('<img'), `${tier.label} 뱃지는 이미지 태그여야 한다`);
  assert.ok(markup.includes(`arena/${tier.key}.svg`), `${tier.label} 뱃지가 제 파일을 안 가리킨다`);
  assert.ok(markup.includes(`alt="${tier.label}"`), `${tier.label} 뱃지에 대체 텍스트가 없다`);
  assert.match(arenaTierBadgeSrc(tier), /\?v=\d+$/, '캐시 무효화 버전이 없으면 색을 바꿔도 옛 뱃지가 남는다');
}
// 티어마다 실루엣이 달라야 작게 봐도 구분된다. 색만 다르면 축소했을 때 전부 같아 보인다.
const silhouettes = new Set();
for (const tier of [...ARENA_RULES.tiers, ARENA_RULES.challengerTier]) {
  const svg = await readFile(new URL(`${tier.key}.svg`, badgeDir), 'utf8');
  // 방패 틀과 색 정의를 걷어내고 장식만 남겨 비교한다.
  const ornament = svg.slice(svg.indexOf('opacity=".62"/>')).replace(/#[0-9a-f]{6}/gi, '');
  assert.ok(!silhouettes.has(ornament), `${tier.label} 장식이 다른 티어와 똑같다`);
  silhouettes.add(ornament);
}
// 인자를 안 주면 최하위 티어로 떨어져야 한다(호출부가 터지지 않게).
assert.ok(arenaTierBadgeMarkup(null).includes(`arena/${ARENA_RULES.tiers[0].key}.svg`));

// --- 레이팅 ---
assert.equal(arenaExpectedScore(1000, 1000), 0.5, '동점 상대 기대승률은 50%');
assert.ok(arenaExpectedScore(1400, 1000) > 0.9, '400점 위면 기대승률이 90%를 넘는다');
// 지는 쪽 감소폭은 이기는 쪽 상승폭보다 작아야 한다. 연패해도 복귀가 덜 막막해진다.
assert.equal(ARENA_RULES.lossDeltaScale, 0.85);
assert.equal(arenaRatingDelta(1000, 1000, true), Math.round(ARENA_RULES.eloK / 2));
assert.equal(
  arenaRatingDelta(1000, 1000, false),
  -Math.round(ARENA_RULES.eloK / 2 * ARENA_RULES.lossDeltaScale),
);
// 어떤 점수 조합에서도 패배폭이 승리폭을 넘으면 안 된다.
for (const [me, foe] of [[1000, 1000], [1000, 1200], [1200, 1000], [1000, 1400], [1400, 1000], [800, 2400]]) {
  for (const role of ['attacker', 'defender']) {
    const up = arenaRatingDelta(me, foe, true, role);
    const down = Math.abs(arenaRatingDelta(me, foe, false, role));
    assert.ok(down <= Math.abs(ARENA_RULES.eloK), `${me}vs${foe} ${role} 감소폭이 K 를 넘는다`);
    // 같은 기대승률에서 재면 감소폭이 상승폭의 보정 비율만큼 작아야 한다.
    const expected = arenaExpectedScore(me, foe);
    const roleScale = role === 'defender' ? ARENA_RULES.defenderDeltaScale : 1;
    assert.equal(down, Math.abs(Math.round(ARENA_RULES.eloK * roleScale * ARENA_RULES.lossDeltaScale * -expected)));
    assert.equal(up, Math.round(ARENA_RULES.eloK * roleScale * (1 - expected)));
  }
}
// 약한 상대를 이겨도 적게 오르고, 강한 상대를 이기면 많이 오른다.
assert.ok(
  arenaRatingDelta(1000, 1400, true) > arenaRatingDelta(1400, 1000, true),
  '언더독 승리가 더 많이 올라야 한다',
);
// 변동폭이 K 를 넘으면 안 된다.
for (const [a, b] of [[800, 2400], [2400, 800], [1000, 1000]]) {
  assert.ok(Math.abs(arenaRatingDelta(a, b, true)) <= ARENA_RULES.eloK);
  assert.ok(Math.abs(arenaRatingDelta(a, b, false)) <= ARENA_RULES.eloK);
}
// 방어는 본인이 고른 판이 아니라 하루 수십 번 당하므로 변동폭이 공격보다 작아야 한다.
assert.equal(ARENA_RULES.defenderDeltaScale, 0.8);
for (const [a, b] of [[1000, 1000], [1000, 1400], [1400, 1000], [2200, 1800]]) {
  for (const won of [true, false]) {
    const attack = Math.abs(arenaRatingDelta(a, b, won, 'attacker'));
    const defend = Math.abs(arenaRatingDelta(a, b, won, 'defender'));
    assert.ok(defend <= attack, `방어 변동폭(${defend})이 공격(${attack})보다 크면 안 된다`);
  }
}
assert.equal(
  arenaRatingDelta(1000, 1000, true, 'defender'),
  Math.round(ARENA_RULES.eloK * ARENA_RULES.defenderDeltaScale / 2),
);
// 역할을 안 넘기면 공격자 기준이어야 한다(기존 호출부가 조용히 약해지면 안 된다).
assert.equal(arenaRatingDelta(1000, 1200, true), arenaRatingDelta(1000, 1200, true, 'attacker'));
assert.equal(applyArenaRating(1000, 1000, true), 1000 + arenaRatingDelta(1000, 1000, true, 'attacker'));
assert.equal(
  applyArenaRating(1000, 1000, true, 'defender'),
  1000 + arenaRatingDelta(1000, 1000, true, 'defender'),
);

// 하한 아래로는 안 떨어진다. 연패해도 무한정 내려가면 복귀가 불가능해진다.
let sinking = ARENA_RULES.minRating;
for (let index = 0; index < 50; index += 1) sinking = applyArenaRating(sinking, 2400, false);
assert.equal(sinking, ARENA_RULES.minRating, '하한 아래로 내려가면 안 된다');

// --- 주간 부분 초기화 ---
assert.equal(arenaSeasonReset(ARENA_RULES.startRating), ARENA_RULES.startRating, '시작 점수는 그대로다');
assert.equal(arenaSeasonReset(2200), 1600, '2200 은 절반 당겨 1600');
assert.ok(arenaSeasonReset(2400) > arenaSeasonReset(2000), '초기화 후에도 순서는 유지된다');
assert.ok(arenaSeasonReset(ARENA_RULES.minRating) >= ARENA_RULES.minRating, '초기화가 하한을 깨면 안 된다');

// --- 주간 보상 ---
assert.equal(arenaWeeklyReward(1), 300_000);
assert.equal(arenaWeeklyReward(3), 300_000);
assert.equal(arenaWeeklyReward(4), 200_000);
assert.equal(arenaWeeklyReward(30), 200_000);
assert.equal(arenaWeeklyReward(31), 100_000);
assert.equal(arenaWeeklyReward(100), 100_000);
assert.equal(arenaWeeklyReward(101), 50_000);
assert.equal(arenaWeeklyReward(9999), 50_000);
// 구간이 겹치거나 역전되면 상위 등수가 더 적게 받는 사고가 난다.
const brackets = ARENA_RULES.weeklyRewards;
for (let index = 1; index < brackets.length; index += 1) {
  assert.ok(brackets[index].points < brackets[index - 1].points, '보상은 등수가 낮을수록 적어야 한다');
  if (brackets[index].maxRank != null) {
    assert.ok(brackets[index].maxRank > brackets[index - 1].maxRank, '등수 구간은 커져야 한다');
  }
}
assert.equal(brackets[brackets.length - 1].maxRank, null, '마지막 구간은 참여자 전원이어야 한다');

// --- 편성 -> 의사 스테이지 환산 ---
const strong = deck(['amplify', 'sustain', 'weaken', 'heavy', 'combo'], 'SSS', 9);
const weak = deck(['amplify', 'sustain', 'weaken', 'heavy', 'combo'], 'A', 0);
const strongStage = formationAsStage(strong, {}, 'test-strong');
const weakStage = formationAsStage(weak, {}, 'test-weak');
assert.ok(strongStage.enemyHp > weakStage.enemyHp, '강한 편성이 더 두꺼워야 한다');
assert.ok(strongStage.enemyAttack > weakStage.enemyAttack, '강한 편성이 더 세게 때려야 한다');
assert.equal(strongStage.boss, false, '보스 계수가 붙으면 보스 특성만 과대평가된다');
assert.ok(Number.isInteger(strongStage.enemyHp) && strongStage.enemyHp > 0);
assert.ok(Number.isInteger(strongStage.enemyAttack) && strongStage.enemyAttack > 0);

// --- 매치 판정 ---
const strongWins = resolveArenaMatch({ attacker: strong, defender: weak, matchId: 'm1' });
assert.equal(strongWins.attackerWon, true, '강한 쪽이 이겨야 한다');
const weakLoses = resolveArenaMatch({ attacker: weak, defender: strong, matchId: 'm1' });
assert.equal(weakLoses.attackerWon, false, '약한 쪽이 공격해도 져야 한다');

// 같은 입력이면 항상 같은 결과여야 서버 재현 검증이 성립한다.
const repeated = resolveArenaMatch({ attacker: strong, defender: weak, matchId: 'm1' });
assert.deepEqual(repeated, strongWins, '같은 매치는 같은 결과여야 한다');
// matchId 가 전투 시드에 들어가므로 다른 매치는 독립적으로 굴러간다.
const other = resolveArenaMatch({ attacker: strong, defender: weak, matchId: 'm2' });
assert.notEqual(other.matchId, strongWins.matchId);

// 승패는 반드시 한쪽으로 정해져야 한다. 무승부가 나오면 레이팅 계산이 막힌다.
for (const matchId of ['a', 'b', 'c', 'd', 'e']) {
  const mirror = resolveArenaMatch({ attacker: strong, defender: strong, matchId });
  assert.equal(typeof mirror.attackerWon, 'boolean', '동일 편성끼리도 승패가 갈려야 한다');
  assert.ok(['knockout', 'speed', 'survival', 'damage'].includes(mirror.reason));
}

// 편성 인원이 안 맞으면 조용히 통과시키지 말고 막아야 한다.
assert.throws(() => resolveArenaMatch({ attacker: strong.slice(0, 4), defender: weak }));
assert.throws(() => resolveArenaMatch({ attacker: strong, defender: weak.slice(0, 3) }));
assert.equal(GAME_RULES.formationSize, 5);

// --- 전투 연출 배선 ---
// 연출은 서버가 낸 수치로만 그려야 한다. 클라이언트가 다시 계산하면 방어자의
// 도감·길드 보너스를 몰라 서버 판정과 어긋난 장면이 나온다.
const controllerSource = await readFile(new URL('../src/renewal/minigame-controller.js', import.meta.url), 'utf8');
const indexSource = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const mainStyles = await readFile(new URL('../styles/renewal/main.css', import.meta.url), 'utf8');
const arenaGuildRankingMigration = await readFile(
  new URL('../supabase/migrations/20260809190206_arena_ranking_guild_names.sql', import.meta.url),
  'utf8',
);
assert.match(controllerSource, /row\.guildName/);
assert.match(controllerSource, /class="arena-rank-identity"/);
assert.match(controllerSource, /class="arena-rank-guild"/);
assert.match(mainStyles, /\.arena-rank-identity \{[^}]*display: flex;[^}]*min-width: 0;/);
assert.match(mainStyles, /\.arena-rank-guild \{[^}]*color: var\(--dim\);/);
assert.match(arenaGuildRankingMigration, /'guildName', ranked\.guild_name/);
assert.match(arenaGuildRankingMigration, /left join public\.gacha_s2_guild_members guild_member/);
assert.match(arenaGuildRankingMigration, /guild\.disbanded_at is null/);
assert.match(controllerSource, /function playArenaBattle\(result\)/, '전투 연출 함수가 있어야 한다');
assert.match(controllerSource, /result\?\.battle/, '연출은 서버가 준 battle 을 써야 한다');
assert.doesNotMatch(controllerSource, /resolveArenaMatch/, '클라이언트가 전투를 다시 계산하면 안 된다');
// 내 체력은 상대가 넣은 피해만큼 줄어야 한다. 좌우가 뒤집히면 이겨도 내 바가 비어 보인다.
assert.match(controllerSource, /1 - Number\(battle\.defenderSide\?\.damageRatio/, '내 바는 상대 피해로 깎여야 한다');
assert.match(controllerSource, /1 - Number\(battle\.attackerSide\?\.damageRatio/, '상대 바는 내 피해로 깎여야 한다');
// 승패를 먼저 띄우면 연출이 의미가 없다.
assert.match(controllerSource, /dataset\.phase = result\.won/, '승패 표시가 있어야 한다');
assert.match(controllerSource, /clearArenaBattleTimers/, '탭을 옮기면 연출 타이머를 정리해야 한다');

// 연출은 미니게임 패널 안이 아니라 모달로 띄운다.
assert.match(controllerSource, /arenaBattleDialog\.showModal\(\)/, '전투는 모달로 띄워야 한다');
assert.match(indexSource, /<dialog class="arena-battle-dialog" id="arenaBattleDialog">/, '전투 모달 마크업이 있어야 한다');
// 인라인 패널이 남아 있으면 같은 내용이 두 곳에 그려진다.
assert.doesNotMatch(indexSource, /id="arenaBattle"[\s>]/, '인라인 전투 패널은 제거돼야 한다');

// 승패가 뜨기까지 최소 4초는 끌어야 연출로 읽힌다. 1.5초는 결과 통보에 가깝다.
const timelineSource = controllerSource.match(/ARENA_BATTLE_TIMELINE = Object\.freeze\(\{[\s\S]*?\}\)/)?.[0] ?? '';
const timelineTotal = [...timelineSource.matchAll(/:\s*(\d+)/g)]
  .reduce((sum, match) => sum + Number(match[1]), 0);
assert.ok(timelineTotal >= 4000, `연출 길이가 너무 짧다: ${timelineTotal}ms`);

// ESC 나 닫기로 창을 닫아도 남은 타이머가 계속 돌면 안 된다.
assert.match(controllerSource, /arenaBattleDialog\?\.addEventListener\('close'/, '모달을 닫으면 타이머를 정리해야 한다');

const routerSource = await readFile(new URL('../src/renewal/server-command-router.js', import.meta.url), 'utf8');
assert.match(routerSource, /p_attacker_side: resolved\.attacker/, '라우터가 연출 수치를 넘겨야 한다');
assert.match(routerSource, /p_defender_side: resolved\.defender/, '라우터가 연출 수치를 넘겨야 한다');

// 회귀: 투기장에 연습 모드가 노출돼 연습으로 돌려도 레이팅이 올랐다.
// miniGameMode.hidden 을 두 곳에서 쓰는데 뒤쪽 줄이 앞줄을 덮어써서 토글이 되살아났다.
const modeToggleLines = controllerSource.match(/elements\.miniGameMode\.hidden = [^;]+;/g) ?? [];
assert.ok(modeToggleLines.length > 0, '모드 토글 제어를 찾지 못했다');
for (const line of modeToggleLines) {
  assert.match(line, /arena/, `투기장에서 연습 토글이 되살아난다: ${line}`);
}
// 연습 상태로 투기장에 들어와도 값이 남지 않도록 보상으로 되돌려야 한다.
assert.match(
  controllerSource,
  /if \(selectedGame === 'arena'\) selectedMode = 'reward';/,
  '투기장 진입 시 보상 모드로 되돌려야 한다',
);

// 회귀: 로또 화면 밑에 투기장 정보(레이팅·전적·승패 가이드)가 그대로 딸려 나왔다.
// renderLotto 가 숨길 패널을 직접 나열하면서 나중에 추가된 arenaShell 을 빼먹은 탓이다.
// 각 render 함수는 전부 숨기는 헬퍼를 부른 뒤 자기 것만 켜야 한다.
assert.match(controllerSource, /function hideMiniGamePanels\(\)/, '패널을 한 번에 숨기는 헬퍼가 있어야 한다');
const panelList = controllerSource.match(/const MINI_GAME_PANELS = \[([^\]]+)\]/)?.[1] ?? '';
for (const panel of ['miniGameEmpty', 'memoryBoard', 'sumTenShell', 'ladderShell', 'lottoShell', 'arenaShell', 'miniGameResult']) {
  assert.ok(panelList.includes(`'${panel}'`), `${panel} 이 숨김 목록에 있어야 한다`);
}
// 어떤 render 함수도 패널을 손으로 숨기면 안 된다. 하나라도 빠지면 화면이 겹친다.
for (const render of ['renderReady', 'renderResult', 'renderMemory', 'renderSumTen', 'renderLadder', 'renderArena', 'renderLotto']) {
  const body = controllerSource.slice(controllerSource.indexOf(`function ${render}(`));
  // 함수 첫 문단(빈 줄 전까지)만 본다. 패널 표시는 전부 여기서 끝나야 한다.
  const head = body.split(/\r?\n\s*\r?\n/)[0];
  assert.ok(head.includes('hideMiniGamePanels();'), `${render} 가 헬퍼를 불러야 한다`);
  assert.doesNotMatch(head, /elements\.\w+\.hidden = true;/, `${render} 가 패널을 손으로 숨기면 안 된다`);
}

// 좌측 메뉴 라벨도 회차 상한을 따라가야 한다. 1~18 회차가 남아 있는 동안 6/16 으로
// 고정돼 있으면 헤더와 숫자판이 서로 다른 값을 말한다.
assert.match(controllerSource, /elements\.lottoNavRange\.textContent = lottoRange/, '메뉴 라벨이 회차 상한을 따라야 한다');
assert.match(indexSource, /id="lottoNavRange"/, '메뉴 라벨에 id 가 있어야 한다');

// 서버가 같은 보정을 안 쓰면 화면에 뜬 변동값과 실제 반영값이 어긋난다.
const lossMigration = await readFile(
  new URL('../supabase/migrations/20260806220432_arena_softer_loss_delta.sql', import.meta.url),
  'utf8',
);
assert.match(lossMigration, /lossDeltaScale/, '서버 설정에 패배 보정이 있어야 한다');
assert.match(lossMigration, /then 1 else v_loss_scale end/, '공격자 패배에 보정이 걸려야 한다');
assert.match(lossMigration, /then v_loss_scale else 1 end/, '방어자 패배에 보정이 걸려야 한다');

// 회귀: 상대 선정에서 스트리머 계정을 빼는 조건이 요청 없이 들어가 있었다.
// 그 결과 스트리머는 랭킹에는 오르면서 방어는 한 번도 당하지 않아, 공격만 하고
// 잃을 일이 없는 구조가 됐다. 랭킹에 오르면 방어도 당해야 한다.
const openMatchMigration = await readFile(
  new URL('../supabase/migrations/20260806005949_arena_match_rpcs.sql', import.meta.url),
  'utf8',
);
const streamerFixMigration = await readFile(
  new URL('../supabase/migrations/20260808110047_arena_allow_streamers_as_defenders.sql', import.meta.url),
  'utf8',
);
// 원본에는 남아 있고(이력 보존), 뒤 마이그레이션이 걷어낸다.
assert.match(openMatchMigration, /acc\.is_streamer = false/, '원본 마이그레이션은 그대로 둔다');
assert.match(streamerFixMigration, /replace\(v_src, E'      and acc\.is_streamer = false/, '스트리머 조건을 걷어내야 한다');
assert.match(streamerFixMigration, /streamer filter survived/, '제거 여부를 검증해야 한다');
// 접속 금지 계정은 계속 제외돼야 한다. 같이 걷어내면 정지된 계정이 방어자로 뽑힌다.
assert.match(streamerFixMigration, /disabled filter was lost/, '비활성 계정 제외는 지켜야 한다');
assert.match(streamerFixMigration, /formation filter was lost/, '편성 5장 조건은 지켜야 한다');
assert.match(streamerFixMigration, /rating band filter was lost/, '레이팅 폭 조건은 지켜야 한다');

// --- 운영 수치 ---
assert.equal(ARENA_RULES.attemptsPerHour, 3);
assert.equal(ARENA_RULES.energyCost, 5);
assert.equal(ARENA_RULES.challengerSlots, 5);
// 탐색 폭은 넓어지는 순서여야 한다. 좁은 쪽부터 찾아야 비슷한 상대가 걸린다.
const bands = ARENA_RULES.matchRatingBands;
assert.deepEqual(bands, [...bands].sort((left, right) => left - right), '매칭 폭은 넓어지는 순서여야 한다');
assert.ok(bands.length > 0);

console.log(
  `arena tests passed: ${ARENA_RULES.tiers.length} tiers + challenger top ${ARENA_RULES.challengerSlots}, `
  + `K=${ARENA_RULES.eloK}, ${ARENA_RULES.attemptsPerHour}/hour at ${ARENA_RULES.energyCost} energy`,
);
