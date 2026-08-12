import { ARENA_RULES, RARITIES } from './config.js';
import { arenaTierBadgeMarkup, arenaTierBadgeSrc, arenaTierFor } from './arena.js';
import {
  MINI_GAME_RULES,
  applySumSelection,
  calculateMiniGameReward,
  capMiniGameReward,
  createLadderBoard,
  createMemoryDeck,
  createSumTenBoard,
  evaluateSumSelection,
  hasValidSumMove,
  normalizeMiniGameProgress,
  pickLadderReward,
  reshuffleSumTiles,
} from './minigames.js';
import { escapeHtml } from './html.js';
import {
  LOTTO_RULES,
  lottoBallMarkup,
  normalizeLottoNumbers,
  pickRandomLottoNumbers,
} from './lotto.js';
import {
  MARKET_ASSETS,
  MARKET_PRODUCTS,
  MARKET_RULES,
  marketFee,
  marketProductLabel,
  marketReturnRate,
  normalizeMarketProduct,
  normalizeMarketQuantity,
} from './market.js';

const number = new Intl.NumberFormat('ko-KR');

function formatTime(seconds) {
  const value = Math.max(0, Math.ceil(seconds));
  return `${String(Math.floor(value / 60)).padStart(2, '0')}:${String(value % 60).padStart(2, '0')}`;
}

function imagePath(card) {
  return `assets/cards/${encodeURIComponent(card.file)}`;
}

function wait(ms) {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

export function createMiniGameController({ cards, getState, persist, showToast, clock, random, serverCommands = null }) {
  if (typeof random !== 'function') throw new TypeError('minigame random adapter is required');
  const elements = Object.fromEntries([
    'minigameScreen', 'miniGamePicker', 'miniGameDaily', 'miniGameDailyBar',
    'miniGameEyebrow', 'miniGameTitle', 'miniGameTimer', 'miniGameScore',
    'miniGameStage', 'miniGameEmpty', 'miniGameReadyVisual', 'miniGameReadyTitle',
    'miniGameReadyCopy', 'miniGameReadyMode', 'miniGameStatus', 'memoryBoard', 'sumTenShell',
    'sumTenBoard', 'miniGameSelectionSum', 'miniGameResult', 'miniGameResultTitle',
    'miniGameResultScore', 'miniGameResultReward', 'miniGameMode', 'miniGameDifficulty',
    'miniGameBest', 'miniGamePlays', 'miniGameRemaining', 'miniGameStartButton',
    'miniGameStopButton', 'miniGameRewardCost', 'ladderShell', 'ladderChoiceCopy', 'ladderBoard',
    'miniGameDailyBlock', 'miniGameControlEyebrow', 'miniGameControlTitle', 'miniGameRecords',
    'lottoNavRange', 'lottoShell', 'lottoRoundLabel', 'lottoSaleStatus', 'lottoNumberGrid',
    'lottoSelectedNumbers', 'lottoMyTicket', 'lottoLatestResult', 'lottoWinnerList',
    'lottoControl', 'lottoFirstPool', 'lottoSecondPool', 'lottoEntryStatus',
    'lottoAutoPickButton', 'lottoHistoryButton', 'lottoHistoryDialog', 'lottoHistoryList',
    'arenaShell', 'arenaTier', 'arenaRating', 'arenaRankLabel', 'arenaRankingButton',
    'arenaAttempts', 'arenaAttackRecord', 'arenaDefendRecord', 'arenaLastMatch',
    'arenaRecentList', 'arenaRankingDialog', 'arenaRankingList',
    'arenaBattleDialog', 'arenaBattleStage', 'arenaBattlePhase', 'arenaBattleClose',
    'arenaBattleVs', 'arenaBattleMeBadge', 'arenaBattleMeName', 'arenaBattleMeRating',
    'arenaBattleMeCards', 'arenaBattleMeBar', 'arenaBattleMeHp',
    'arenaBattleFoeBadge', 'arenaBattleFoeName', 'arenaBattleFoeRating',
    'arenaBattleFoeCards', 'arenaBattleFoeBar', 'arenaBattleFoeHp',
    'arenaBattleResult', 'arenaBattleVerdict', 'arenaBattleReason', 'arenaBattleDelta',
    'arenaBattleSkip',
    'marketShell', 'marketNextUpdate', 'marketAssetList', 'marketSelectedImage',
    'marketSelectedSymbol', 'marketSelectedName', 'marketSelectedProduct', 'marketSelectedPrice', 'marketSelectedChange',
    'marketChart', 'marketOwnedQuantity', 'marketAveragePrice', 'marketPositionValue',
    'marketPositionPnl', 'marketQuantity', 'marketMaxBuy', 'marketMaxSell',
    'marketProductSelect', 'marketProductRisk', 'marketOrderGross', 'marketOrderFee', 'marketBuyButton', 'marketSellButton',
    'marketControl', 'marketInvestedPoints', 'marketValue', 'marketUnrealizedPnl',
    'marketRealizedPnl', 'marketInvestmentCap', 'marketInvestmentBar', 'marketTradeList',
  ].map((id) => [id, document.getElementById(id)]));

  let selectedGame = 'memory';
  let selectedMode = 'reward';
  let memoryDifficulty = 'basic';
  let session = null;
  let timer = 0;
  let resolvingMemory = false;
  let sumDrag = null;
  let ladderResolving = false;
  let lottoState = null;
  let lottoNumbers = [];
  let lottoLoading = false;
  let lottoNextSyncAt = 0;
  let lottoRequestSequence = 0;
  let arenaState = null;
  let arenaLoading = false;
  let arenaLastResult = null;
  let arenaBattleTimers = [];
  let arenaBattleFrames = [];
  let arenaBattleSkip = null;
  let marketState = null;
  let marketLoading = false;
  let marketNextSyncAt = 0;
  let marketSelectedSymbol = MARKET_ASSETS[0].symbol;
  let marketSelectedProductKey = MARKET_PRODUCTS[0].key;
  let result = null;
  let sequence = 0;

  function progress() {
    const state = getState();
    state.miniGames = normalizeMiniGameProgress(state.miniGames, clock.now());
    return state.miniGames;
  }

  function sessionRemaining() {
    return session ? Math.max(0, Math.ceil((session.endAt - clock.now()) / 1000)) : 0;
  }

  function currentScore() {
    return session?.score ?? result?.score ?? 0;
  }

  function renderHeader() {
    const memory = selectedGame === 'memory';
    const ladder = selectedGame === 'ladder';
    const lotto = selectedGame === 'lotto';
    const arena = selectedGame === 'arena';
    const market = selectedGame === 'market';
    // 회차마다 상한이 다르다. 좌측 메뉴 라벨도 같은 값을 써야 6/18 회차가 남아 있는
    // 동안 헤더와 숫자가 어긋나지 않는다.
    const lottoRange = `LOTTO 6/${currentLottoMaxNumber()}`;
    if (elements.lottoNavRange) elements.lottoNavRange.textContent = lottoRange;
    elements.miniGameEyebrow.textContent = market ? 'CALMS EXCHANGE'
      : arena ? 'ARENA PVP'
      : memory ? 'MEMORY SIGNAL' : ladder ? 'LUCKY LADDER' : lotto ? lottoRange : 'CAMMON APPLE';
    elements.miniGameTitle.textContent = market ? MARKET_RULES.label
      : arena ? '투기장'
      : memory ? '카드 짝맞추기' : ladder ? MINI_GAME_RULES.ladder.label : lotto ? '시그널 로또' : MINI_GAME_RULES.sumTen.label;
    elements.miniGameTimer.textContent = market ? marketCountdownLabel()
      : arena ? arenaResetLabel()
      : lotto ? lottoCountdownLabel() : ladder ? '--:--' : formatTime(session ? sessionRemaining() : (
        memory ? MINI_GAME_RULES.memory[memoryDifficulty].timeLimit : MINI_GAME_RULES.sumTen.timeLimit
      ));
    if (market) {
      elements.miniGameScore.textContent = `${number.format(marketState?.assets?.length ?? MARKET_ASSETS.length)} 종목`;
    } else if (arena) {
      elements.miniGameScore.textContent = arenaState
        ? `${number.format(arenaRemainingAttempts())} / ${number.format(arenaState.attemptsPerHour ?? ARENA_RULES.attemptsPerHour)}`
        : '-';
    } else {
      const lottoTickets = currentLottoTickets();
      elements.miniGameScore.textContent = lotto
        ? lottoTickets.length >= LOTTO_RULES.ticketLimit
          ? `${lottoTickets.length} / ${LOTTO_RULES.ticketLimit}`
          : `${lottoNumbers.length} / ${LOTTO_RULES.picks}`
        : number.format(currentScore());
    }
  }

  function renderControls() {
    const daily = progress();
    const ladder = selectedGame === 'ladder';
    const lotto = selectedGame === 'lotto';
    const arena = selectedGame === 'arena';
    const market = selectedGame === 'market';
    elements.minigameScreen.classList.toggle('market-mode', market);
    const earned = daily.pointsEarnedByGame[selectedGame] ?? 0;
    const remaining = Math.max(0, MINI_GAME_RULES.dailyPointCapPerGame - earned);
    const busy = Boolean(session);
    const energyCost = ladder ? MINI_GAME_RULES.ladder.energyCost : MINI_GAME_RULES.energyCost;
    elements.miniGameDailyBlock.hidden = lotto || arena || market;
    elements.miniGameMode.hidden = lotto || arena || market;
    elements.miniGameRecords.hidden = lotto || arena || market;
    elements.lottoControl.hidden = !lotto;
    elements.marketControl.hidden = !market;
    elements.miniGameControlEyebrow.textContent = market ? 'ACCOUNT BOOK'
      : arena ? 'LADDER CONTROL' : lotto ? 'DRAW CONTROL' : 'PLAY MODE';
    elements.miniGameControlTitle.textContent = market ? '투자 현황'
      : arena ? '투기장 정보' : lotto ? '구매 정보' : '작전 설정';
    if (!lotto && !arena && !market) {
      elements.miniGameDaily.textContent = `${number.format(earned)} / ${number.format(MINI_GAME_RULES.dailyPointCapPerGame)} P`;
      elements.miniGameDailyBar.style.width = `${Math.min(100, earned / MINI_GAME_RULES.dailyPointCapPerGame * 100)}%`;
    }
    elements.miniGameBest.textContent = number.format(selectedGame === 'memory' ? daily.bestMemory : ladder ? daily.bestLadder : daily.bestSumTen);
    elements.miniGamePlays.textContent = `${number.format(daily.plays)}회`;
    elements.miniGameRemaining.textContent = `${number.format(remaining)} P`;
    elements.miniGameDifficulty.hidden = selectedGame !== 'memory' || lotto || market;
    // 투기장에는 연습이 없다. 레이팅이 실제로 움직이는 판이라 연습 개념이 성립하지 않는다.
    elements.miniGameMode.hidden = lotto || ladder || arena || market;
    elements.miniGameStartButton.hidden = busy || market;
    elements.miniGameStopButton.hidden = !busy;
    elements.miniGameStopButton.disabled = ladderResolving;
    const lottoTicketCount = currentLottoTickets().length;
    elements.miniGameStartButton.disabled = arena
      ? arenaLoading || arenaRemainingAttempts() <= 0 || getState().actionEnergy < ARENA_RULES.energyCost
      : lotto
      ? lottoLoading
        || !lottoState?.round?.saleOpen
        || lottoTicketCount >= LOTTO_RULES.ticketLimit
        || normalizeLottoNumbers(lottoNumbers).length !== LOTTO_RULES.picks
        || getState().points < LOTTO_RULES.ticketCost
      : (ladder || selectedMode === 'reward')
      && (getState().actionEnergy < energyCost || remaining <= 0);
    elements.miniGameStartButton.querySelector('span').textContent = arena
      ? arenaRemainingAttempts() <= 0
        ? '이번 시간 횟수 소진'
        : `상대 찾기 · 행동력 ${ARENA_RULES.energyCost}`
      : lotto
      ? lottoTicketCount >= LOTTO_RULES.ticketLimit
        ? '이번 회차 2장 구매 완료'
        : `${lottoTicketCount + 1}번째 티켓 1,000P 구매`
      : ladder ? '출발점 선택하기' : selectedMode === 'reward' ? '보상 게임 시작' : '연습 시작';
    elements.miniGameStartButton.dataset.mode = lotto || ladder || arena ? 'reward' : selectedMode;
    elements.miniGameRewardCost.textContent = arena
      ? `-${ARENA_RULES.energyCost} 행동력`
      : `-${energyCost} 행동력`;
    elements.miniGameRewardCost.textContent = `-${energyCost} 행동력`;
    elements.miniGamePicker.querySelectorAll('[data-minigame-select]').forEach((button) => {
      button.classList.toggle('active', button.dataset.minigameSelect === selectedGame);
      button.disabled = busy;
    });
    elements.miniGameMode.querySelectorAll('[data-mini-mode]').forEach((button) => {
      button.classList.toggle('active', button.dataset.miniMode === selectedMode);
      button.disabled = busy;
    });
    elements.miniGameDifficulty.querySelectorAll('[data-memory-difficulty]').forEach((button) => {
      button.classList.toggle('active', button.dataset.memoryDifficulty === memoryDifficulty);
      button.disabled = busy;
    });
  }

  // 미니게임 화면은 한 번에 하나만 떠야 한다. 각 render 함수가 숨길 목록을 따로 적으면
  // 새 게임을 추가할 때 한 곳을 빼먹고 두 화면이 겹쳐 보인다(로또 밑에 투기장이 딸려 나왔다).
  // 전부 숨긴 뒤 자기 것만 켜는 방식으로 통일한다.
  const MINI_GAME_PANELS = ['miniGameEmpty', 'memoryBoard', 'sumTenShell', 'ladderShell', 'lottoShell', 'arenaShell', 'marketShell', 'miniGameResult'];

  function hideMiniGamePanels() {
    MINI_GAME_PANELS.forEach((name) => { if (elements[name]) elements[name].hidden = true; });
  }

  function renderReady() {
    const rules = MINI_GAME_RULES.memory[memoryDifficulty];
    const ladder = selectedGame === 'ladder';
    const previewCard = cards.find((card) => card.id === 'kimyunhwan-2') ?? cards.find((card) => card.rarity !== 'EX');
    hideMiniGamePanels();
    elements.miniGameEmpty.hidden = false;
    elements.miniGameReadyVisual.dataset.game = selectedGame;
    elements.miniGameReadyVisual.innerHTML = selectedGame === 'memory'
      ? `<div class="memory-ready-preview"><i class="back"></i><figure style="--rarity:${RARITIES[previewCard.rarity].color}"><img src="${imagePath(previewCard)}" alt=""><b>${previewCard.rarity}</b></figure><figure style="--rarity:${RARITIES[previewCard.rarity].color}"><img src="${imagePath(previewCard)}" alt=""><b>${previewCard.rarity}</b></figure></div>`
      : ladder
        ? `<div class="ladder-ready-preview">${MINI_GAME_RULES.ladder.rewards.map((reward) => `<i>${number.format(reward)}P</i>`).join('')}<b>?</b></div>`
        : `<div class="sum-ready-preview">${[1, 9, 4, 6, 3, 7, 8, 2, 5].map((value, index) => `<i style="--index:${index}"><b>${value}</b></i>`).join('')}<span>10</span></div>`;
    elements.miniGameReadyTitle.textContent = selectedGame === 'memory' ? '같은 카드 신호를 찾아라' : ladder ? '출발점은 직접, 결과는 운명' : '합계 10 카드백을 지워라';
    elements.miniGameReadyCopy.textContent = selectedGame === 'memory'
      ? `카드 2장을 뒤집어 같은 인물의 짝을 완성합니다. 클리어 보상 ${number.format(rules.completionReward)}P.`
      : ladder
        ? '1~6번 출발점 중 하나를 고르면 사다리가 시작됩니다. 선택 순간 행동력 100이 소비됩니다.'
        : `드래그한 사각형 안의 숫자 합이 10이면 카드백 조각이 제거됩니다. 최대 ${number.format(MINI_GAME_RULES.sumTen.maxReward)}P.`;
    elements.miniGameStatus.textContent = selectedGame === 'memory'
      ? `${rules.label} · ${rules.pairs} PAIRS · ${rules.timeLimit} SEC`
      : ladder
        ? MINI_GAME_RULES.ladder.rewards.map((reward) => `${number.format(reward)}P`).join(' · ')
        : `${MINI_GAME_RULES.sumTen.columns}×${MINI_GAME_RULES.sumTen.rows} · ${MINI_GAME_RULES.sumTen.timeLimit} SEC`;
    elements.miniGameReadyMode.textContent = ladder
      ? `보상 전용 · 행동력 ${MINI_GAME_RULES.ladder.energyCost} · 6개 보상 동일 확률`
      : selectedMode === 'reward'
        ? `보상 모드 · 행동력 ${MINI_GAME_RULES.energyCost} · 게임별 일일 최대 ${number.format(MINI_GAME_RULES.dailyPointCapPerGame)} P`
      : '연습 모드 · 행동력 소모 없음 · 포인트 보상 없음';
    elements.miniGameReadyMode.dataset.mode = ladder ? 'reward' : selectedMode;
  }

  function renderResult() {
    hideMiniGamePanels();
    elements.miniGameResult.hidden = false;
    elements.miniGameResultTitle.textContent = result.title;
    elements.miniGameResultScore.textContent = result.scoreLabel ?? `${number.format(result.score)} SCORE`;
    elements.miniGameResultReward.textContent = result.mode === 'practice' ? 'PRACTICE' : `+${number.format(result.reward)} P`;
  }

  function renderMemory() {
    hideMiniGamePanels();
    elements.memoryBoard.hidden = false;
    elements.memoryBoard.style.setProperty('--columns', session.columns);
    elements.memoryBoard.innerHTML = session.deck.map((card, index) => {
      const revealed = session.open.includes(index);
      const matched = session.matched.has(index);
      return `<button class="memory-card${revealed ? ' revealed' : ''}${matched ? ' matched' : ''}" type="button" data-memory-index="${index}" aria-label="${matched ? '완료된 카드' : '뒤집힌 카드'}">
        <span class="memory-card-inner">
          <span class="memory-card-face memory-card-back"></span>
          <span class="memory-card-face memory-card-front" style="--rarity:${RARITIES[card.rarity].color}"><img src="${imagePath(card)}" alt=""><b>${card.rarity}</b><span>${card.member}</span></span>
        </span>
      </button>`;
    }).join('');
  }

  function tilePosition(value, total) {
    return total <= 1 ? 0 : value / (total - 1) * 100;
  }

  function renderSumTen() {
    hideMiniGamePanels();
    elements.sumTenShell.hidden = false;
    elements.sumTenBoard.style.setProperty('--columns', session.columns);
    elements.sumTenBoard.style.setProperty('--rows', session.rows);
    elements.sumTenBoard.innerHTML = session.tiles.map((tile) => `<div class="sum-tile${tile.active ? '' : ' inactive'}" data-sum-index="${tile.index}" style="--tile-x:${tilePosition(tile.column, session.columns)}%;--tile-y:${tilePosition(tile.row, session.rows)}%"><span>${tile.active ? tile.value : ''}</span></div>`).join('');
    elements.miniGameSelectionSum.textContent = '0';
    elements.miniGameSelectionSum.parentElement.classList.remove('invalid');
  }

  function ladderX(lane, columns = MINI_GAME_RULES.ladder.columns) {
    return `${lane / (columns - 1) * 100}%`;
  }

  function ladderY(row, rungRows = MINI_GAME_RULES.ladder.rungRows) {
    return `${(row + 1) / (rungRows + 1) * 100}%`;
  }

  function renderLadder() {
    hideMiniGamePanels();
    elements.ladderShell.hidden = false;
    const columns = MINI_GAME_RULES.ladder.columns;
    const choosing = session.phase === 'choose';
    const board = session.board;
    elements.ladderChoiceCopy.textContent = choosing ? '1~6번 출발점 중 하나를 직접 선택하세요' : session.phase === 'resolved' ? `당첨 +${number.format(session.reward)}P` : '사다리 추적 중...';
    const rails = Array.from({ length: columns }, (_, lane) => `<i class="ladder-rail" style="--x:${ladderX(lane)}"></i>`).join('');
    const rungs = board ? board.rows.flatMap((edges, row) => edges.map((edge) => `<i class="ladder-rung" style="--x:${ladderX(edge)};--y:${ladderY(row, board.rungRows)}"></i>`)).join('') : '';
    const token = board ? `<b class="ladder-token" id="ladderToken" style="--x:${ladderX(session.phase === 'resolved' ? board.endLane : board.startLane)};--y:${session.phase === 'resolved' ? '100%' : '0%'}">${board.startLane + 1}</b>` : '';
    const rewards = board ? board.rewards : MINI_GAME_RULES.ladder.rewards;
    elements.ladderBoard.innerHTML = `
      <div class="ladder-top">${Array.from({ length: columns }, (_, lane) => `<button type="button" data-ladder-lane="${lane}" class="${session.startLane === lane ? 'selected' : ''}" ${choosing ? '' : 'disabled'}>${lane + 1}</button>`).join('')}</div>
      <div class="ladder-track">${rails}${rungs}${token}</div>
      <div class="ladder-bottom">${rewards.map((reward, lane) => `<span class="${board ? '' : 'hidden-reward'}${session.phase === 'resolved' && board?.endLane === lane ? ' winner' : ''}">${board ? `${number.format(reward)}P` : '?'}</span>`).join('')}</div>`;
  }

  function formatLottoRound(drawAt) {
    if (!Number.isFinite(Number(drawAt))) return '회차 확인 중';
    return new Intl.DateTimeFormat('ko-KR', {
      timeZone: 'Asia/Seoul',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(new Date(Number(drawAt)));
  }

  function lottoCountdownLabel() {
    const round = lottoState?.round;
    if (!round) return '--:--';
    if (!round.saleOpen) return '마감';
    return formatTime((Number(round.salesCloseAt) - clock.now()) / 1000);
  }

  function currentLottoTickets() {
    if (Array.isArray(lottoState?.tickets)) return lottoState.tickets;
    return lottoState?.ticket ? [lottoState.ticket] : [];
  }

  // 이번 회차의 번호 상한. 회차는 만들어질 때 상한을 박아두므로 표를 산 뒤에 규칙이
  // 바뀌어도 그 회차는 팔릴 때의 범위를 유지한다. 서버 값이 없으면 설정값으로 떨어진다.
  function currentLottoMaxNumber() {
    const value = Number(lottoState?.round?.maxNumber);
    return Number.isInteger(value) && value >= LOTTO_RULES.picks ? value : LOTTO_RULES.maximumNumber;
  }


  // ── 투기장 ─────────────────────────────────────────────
  function arenaRemainingAttempts() {
    const limit = Number(arenaState?.attemptsPerHour ?? ARENA_RULES.attemptsPerHour);
    const used = Number(arenaState?.attemptsUsed ?? 0);
    return Math.max(0, limit - used);
  }

  // 다음 정각까지 남은 시간. 미사용 횟수는 이월되지 않는다.
  function arenaResetLabel() {
    const resetAt = Number(arenaState?.attemptsResetAt);
    if (!Number.isFinite(resetAt)) return '--:--';
    return formatTime((resetAt - clock.now()) / 1000);
  }

  function arenaReasonLabel(reason) {
    if (reason === 'knockout') return '제압';
    if (reason === 'speed') return '속도 우위';
    if (reason === 'survival') return '생존 우위';
    if (reason === 'damage') return '피해량 우위';
    return '';
  }

  function renderArenaRanking() {
    if (!elements.arenaRankingList) return;
    const rows = Array.isArray(arenaState?.ranking) ? arenaState.ranking : [];
    if (!rows.length) {
      elements.arenaRankingList.innerHTML = '<p>아직 랭킹이 없습니다.</p>';
      return;
    }
    elements.arenaRankingList.innerHTML = rows.map((row) => {
      const tier = arenaTierFor(row.rating, row.rank);
      const guildName = String(row.guildName ?? '').trim();
      return `<article class="arena-rank-row${row.isSelf ? ' self' : ''}">
        <b>${number.format(row.rank)}</b>
        <span class="arena-rank-identity"><span class="arena-rank-name">${escapeHtml(String(row.nickname ?? '-'))}</span>${guildName ? `<span class="arena-rank-guild">[${escapeHtml(guildName)}]</span>` : ''}</span>
        <span class="arena-rank-tier">${arenaTierBadgeMarkup(tier, 20)}${escapeHtml(tier.label)}</span>
        <strong>${number.format(row.rating)}</strong>
        <small>${number.format(row.wins ?? 0)}승 ${number.format(row.losses ?? 0)}패</small>
      </article>`;
    }).join('');
  }

  function renderArena() {
    hideMiniGamePanels();
    elements.arenaShell.hidden = false;

    const rating = Number(arenaState?.rating ?? ARENA_RULES.startRating);
    const rank = Number.isFinite(Number(arenaState?.rank)) ? Number(arenaState.rank) : null;
    const tier = arenaTierFor(rating, rank);
    elements.arenaTier.innerHTML = `${arenaTierBadgeMarkup(tier, 44)}`
      + `<div class="arena-tier-copy"><span>${escapeHtml(tier.key.toUpperCase())}</span><strong>${escapeHtml(tier.label)}</strong></div>`;
    elements.arenaRating.textContent = number.format(rating);
    elements.arenaRankLabel.textContent = rank
      ? `${number.format(rank)}위 / ${number.format(arenaState?.population ?? 0)}명`
      : '순위 집계 전';
    elements.arenaAttempts.textContent = arenaState
      ? `${number.format(arenaRemainingAttempts())}회 · ${arenaResetLabel()} 후 충전`
      : '-';
    elements.arenaAttackRecord.textContent = arenaState
      ? `${number.format(arenaState.wins ?? 0)}승 ${number.format(arenaState.losses ?? 0)}패`
      : '-';
    elements.arenaDefendRecord.textContent = arenaState
      ? `${number.format(arenaState.defendWins ?? 0)}승 ${number.format(arenaState.defendLosses ?? 0)}패`
      : '-';

    if (arenaLastResult) {
      const delta = Number(arenaLastResult.ratingDelta ?? 0);
      elements.arenaLastMatch.dataset.outcome = arenaLastResult.won ? 'win' : 'lose';
      elements.arenaLastMatch.innerHTML = `<b>${arenaLastResult.won ? '승리' : '패배'}</b>`
        + `<span>${escapeHtml(arenaReasonLabel(arenaLastResult.reason))}</span>`
        + `<strong>${delta >= 0 ? '+' : ''}${number.format(delta)}</strong>`;
    } else {
      elements.arenaLastMatch.removeAttribute('data-outcome');
      elements.arenaLastMatch.textContent = '아직 전투 기록이 없습니다';
    }

    const recent = Array.isArray(arenaState?.recentMatches) ? arenaState.recentMatches : [];
    elements.arenaRecentList.innerHTML = recent.length
      ? recent.slice(0, 10).map((row) => {
        const delta = Number(row.ratingDelta ?? 0);
        return `<article class="arena-recent-row" data-outcome="${row.won ? 'win' : 'lose'}">
          <span class="arena-recent-role">${row.role === 'attack' ? '공격' : '방어'}</span>
          <b>${escapeHtml(String(row.opponent ?? '-'))}</b>
          <span>${row.won ? '승' : '패'}</span>
          <strong>${delta >= 0 ? '+' : ''}${number.format(delta)}</strong>
        </article>`;
      }).join('')
      : '기록 대기 중';

    renderArenaRanking();
  }

  // 전투 연출. 서버가 낸 수치로 양쪽 체력바를 깎는다.
  // 클라이언트가 전투를 다시 계산하면 방어자의 도감·길드 보너스를 몰라
  // 서버 판정과 어긋난 장면이 나오므로 재계산하지 않는다.
  function clearArenaBattleTimers() {
    arenaBattleTimers.forEach((id) => window.clearTimeout(id));
    arenaBattleTimers = [];
    arenaBattleFrames.forEach((id) => window.cancelAnimationFrame(id));
    arenaBattleFrames = [];
  }

  function arenaBattleCards(formation) {
    const ids = Array.isArray(formation) ? formation : [];
    return ids.map((cardId) => {
      const card = cards.find((entry) => entry.id === cardId);
      if (!card) return '<i class="arena-battle-card empty"></i>';
      return `<i class="arena-battle-card" style="--rarity:${RARITIES[card.rarity]?.color ?? '#89939b'}">`
        + `<img src="${imagePath(card)}" alt="" loading="lazy" decoding="async"></i>`;
    }).join('');
  }

  // 연출 구간(ms). 승패가 먼저 보이면 볼 이유가 없어지므로 단계를 나눠 뒤에 둔다.
  const ARENA_BATTLE_TIMELINE = Object.freeze({
    intro: 1100,    // 양쪽 편성이 올라오는 구간
    drain: 4200,    // 체력바가 깎이는 구간
    verdict: 700,   // 바가 멈춘 뒤 승패가 찍히기까지의 뜸
  });

  // 체력바를 프레임마다 그린다. CSS transition 은 숫자 표기를 같이 움직일 수 없다.
  function arenaAnimateHp(bar, label, from, to, durationMs) {
    const startedAt = performance.now();
    const step = () => {
      const progress = Math.min(1, (performance.now() - startedAt) / durationMs);
      // 초반이 빠르고 끝이 느리다. 교전이 잦아드는 느낌.
      const ratio = from + (to - from) * (1 - (1 - progress) ** 3);
      bar.style.width = `${(ratio * 100).toFixed(1)}%`;
      bar.dataset.state = ratio <= 0.001 ? 'down' : ratio < 0.3 ? 'critical' : 'ok';
      label.textContent = `${Math.round(ratio * 100)}%`;
      if (progress < 1) arenaBattleFrames.push(window.requestAnimationFrame(step));
    };
    arenaBattleFrames.push(window.requestAnimationFrame(step));
  }

  function finishArenaBattle(result, meLeft, foeLeft) {
    clearArenaBattleTimers();
    elements.arenaBattleMeBar.style.width = `${(meLeft * 100).toFixed(1)}%`;
    elements.arenaBattleFoeBar.style.width = `${(foeLeft * 100).toFixed(1)}%`;
    elements.arenaBattleMeBar.dataset.state = meLeft <= 0.001 ? 'down' : meLeft < 0.3 ? 'critical' : 'ok';
    elements.arenaBattleFoeBar.dataset.state = foeLeft <= 0.001 ? 'down' : foeLeft < 0.3 ? 'critical' : 'ok';
    elements.arenaBattleMeHp.textContent = `${Math.round(meLeft * 100)}%`;
    elements.arenaBattleFoeHp.textContent = `${Math.round(foeLeft * 100)}%`;
    elements.arenaBattleStage.dataset.phase = result.won ? 'win' : 'lose';
    elements.arenaBattlePhase.textContent = result.won ? 'VICTORY' : 'DEFEAT';
    elements.arenaBattleVs.textContent = result.won ? 'WIN' : 'LOSE';
    elements.arenaBattleVerdict.textContent = result.won ? '승리' : '패배';
    elements.arenaBattleReason.textContent = arenaReasonLabel(result.reason);
    const delta = Number(result.ratingDelta ?? 0);
    elements.arenaBattleDelta.textContent = `${number.format(result.ratingBefore ?? 0)} → `
      + `${number.format(result.ratingAfter ?? 0)} (${delta >= 0 ? '+' : ''}${number.format(delta)})`;
    elements.arenaBattleSkip.textContent = '닫으려면 눌러 주세요';
    arenaBattleSkip = null;
  }

  function playArenaBattle(result) {
    const battle = result?.battle;
    if (!battle || !elements.arenaBattleDialog) return;
    clearArenaBattleTimers();

    const meTier = arenaTierFor(result.ratingBefore ?? ARENA_RULES.startRating);
    const foeTier = arenaTierFor(result.opponentRatingBefore ?? ARENA_RULES.startRating);
    elements.arenaBattleMeBadge.src = arenaTierBadgeSrc(meTier);
    elements.arenaBattleMeBadge.alt = meTier.label;
    elements.arenaBattleFoeBadge.src = arenaTierBadgeSrc(foeTier);
    elements.arenaBattleFoeBadge.alt = foeTier.label;
    elements.arenaBattleMeName.textContent = getState().nickname || '나';
    elements.arenaBattleFoeName.textContent = battle.opponent ?? '상대';
    elements.arenaBattleMeRating.textContent = `${number.format(result.ratingBefore ?? 0)} · ${meTier.label}`;
    elements.arenaBattleFoeRating.textContent = `${number.format(result.opponentRatingBefore ?? 0)} · ${foeTier.label}`;
    elements.arenaBattleMeCards.innerHTML = arenaBattleCards(battle.attackerFormation);
    elements.arenaBattleFoeCards.innerHTML = arenaBattleCards(battle.defenderFormation);

    // 내 체력바는 "상대가 나에게 넣은 피해"만큼 줄어든다. 그 반대도 같다.
    const meLeft = Math.max(0, 1 - Number(battle.defenderSide?.damageRatio ?? 0));
    const foeLeft = Math.max(0, 1 - Number(battle.attackerSide?.damageRatio ?? 0));

    elements.arenaBattleStage.dataset.phase = 'intro';
    elements.arenaBattlePhase.textContent = 'MATCH FOUND';
    elements.arenaBattleVs.textContent = 'VS';
    elements.arenaBattleVerdict.textContent = '';
    elements.arenaBattleReason.textContent = '';
    elements.arenaBattleDelta.textContent = '';
    elements.arenaBattleSkip.textContent = '화면을 누르면 건너뜁니다';
    elements.arenaBattleMeBar.style.width = '100%';
    elements.arenaBattleFoeBar.style.width = '100%';
    elements.arenaBattleMeBar.dataset.state = 'ok';
    elements.arenaBattleFoeBar.dataset.state = 'ok';
    elements.arenaBattleMeHp.textContent = '100%';
    elements.arenaBattleFoeHp.textContent = '100%';
    arenaBattleSkip = () => finishArenaBattle(result, meLeft, foeLeft);

    if (!elements.arenaBattleDialog.open) elements.arenaBattleDialog.showModal();
    window.lucide?.createIcons();

    arenaBattleTimers.push(window.setTimeout(() => {
      elements.arenaBattleStage.dataset.phase = 'engage';
      elements.arenaBattlePhase.textContent = 'ENGAGE';
      elements.arenaBattleVs.textContent = '⚔';
      arenaAnimateHp(elements.arenaBattleMeBar, elements.arenaBattleMeHp, 1, meLeft, ARENA_BATTLE_TIMELINE.drain);
      arenaAnimateHp(elements.arenaBattleFoeBar, elements.arenaBattleFoeHp, 1, foeLeft, ARENA_BATTLE_TIMELINE.drain);
    }, ARENA_BATTLE_TIMELINE.intro));

    arenaBattleTimers.push(window.setTimeout(
      () => finishArenaBattle(result, meLeft, foeLeft),
      ARENA_BATTLE_TIMELINE.intro + ARENA_BATTLE_TIMELINE.drain + ARENA_BATTLE_TIMELINE.verdict,
    ));
  }

  async function loadArenaState({ silent = false } = {}) {
    if (!serverCommands?.getArenaState || arenaLoading) return;
    arenaLoading = true;
    if (!silent) render();
    const response = await serverCommands.getArenaState();
    arenaLoading = false;
    if (response?.ok === false) {
      if (!silent) showToast(response.message ?? '투기장 정보를 불러오지 못했습니다.');
      render();
      return;
    }
    arenaState = response;
    render();
  }

  async function startArenaFight() {
    if (arenaLoading || !serverCommands?.arenaFight) return;
    if (arenaRemainingAttempts() <= 0) return showToast('이번 시간대 투기장 횟수를 모두 썼습니다.');
    if (getState().actionEnergy < ARENA_RULES.energyCost) {
      return showToast(`행동력 ${ARENA_RULES.energyCost}이 필요합니다.`);
    }
    arenaLoading = true;
    render();
    const response = await serverCommands.arenaFight();
    arenaLoading = false;
    if (response?.ok === false) {
      showToast(response.message ?? '투기장 전투에 실패했습니다.');
      // 횟수·행동력이 이미 소모됐을 수 있으니 서버 상태를 다시 읽는다.
      await loadArenaState({ silent: true });
      return;
    }
    arenaLastResult = response?.result ?? null;
    if (arenaLastResult) {
      playArenaBattle(arenaLastResult);
      const delta = Number(arenaLastResult.ratingDelta ?? 0);
      showToast(`${arenaLastResult.won ? '승리' : '패배'} · ${delta >= 0 ? '+' : ''}${number.format(delta)} 점`);
    }
    await loadArenaState({ silent: true });
  }

  function marketCountdownLabel() {
    const next = Number(marketState?.nextUpdateAt ?? 0);
    if (!next) return '--:--';
    return formatTime(Math.max(0, (next - clock.now()) / 1000));
  }

  function marketSignedPoints(value) {
    const amount = Math.round(Number(value) || 0);
    return `${amount > 0 ? '+' : ''}${number.format(amount)}P`;
  }

  function marketSignedPercent(value) {
    const amount = Math.abs(Number(value) || 0) < 0.005 ? 0 : Number(value) || 0;
    return `${amount > 0 ? '+' : ''}${amount.toFixed(2)}%`;
  }

  function marketLocalPreview() {
    const hourAt = Math.floor(clock.now() / 3_600_000) * 3_600_000;
    return {
      hourAt,
      nextUpdateAt: hourAt + 3_600_000,
      feeRate: MARKET_RULES.feeRate,
      totalInvestmentCap: MARKET_RULES.totalInvestmentCap,
      perAssetInvestmentCap: MARKET_RULES.perAssetInvestmentCap,
      investedPoints: 0,
      marketValue: 0,
      realizedPnl: 0,
      assets: MARKET_ASSETS.map((asset) => ({
        ...asset,
        investedPoints: 0,
        price: asset.basePrice,
        changeBps: 0,
        regime: 'open',
        quantity: 0,
        costBasis: 0,
        averagePrice: 0,
        marketValue: 0,
        unrealizedPnl: 0,
        history: [{ at: hourAt, price: asset.basePrice }],
        positions: MARKET_PRODUCTS.map((product) => ({
          positionType: product.positionType,
          multiplier: product.multiplier,
          label: product.label,
          price: asset.basePrice,
          changeBps: 0,
          quantity: 0,
          costBasis: 0,
          averagePrice: 0,
          marketValue: 0,
          unrealizedPnl: 0,
          liquidationPrice: 0,
          history: [{ at: hourAt, price: asset.basePrice }],
        })),
      })),
      recentTrades: [],
    };
  }

  function currentMarketAsset() {
    const assets = Array.isArray(marketState?.assets) ? marketState.assets : [];
    return assets.find((asset) => asset.symbol === marketSelectedSymbol) ?? assets[0] ?? null;
  }

  function currentMarketProduct() {
    const [positionType, multiplier] = marketSelectedProductKey.split(':');
    return normalizeMarketProduct(positionType, Number(multiplier));
  }

  function currentMarketPosition(asset = currentMarketAsset()) {
    if (!asset) return null;
    const product = currentMarketProduct();
    const positions = Array.isArray(asset.positions) ? asset.positions : [];
    return positions.find((position) => (
      position.positionType === product.positionType && Number(position.multiplier) === product.multiplier
    )) ?? (product.key === 'long:1' ? asset : null);
  }

  function marketProductRiskText(product, position) {
    if (product.multiplier === 1) return '기초 종목과 같은 방향으로 움직이며 강제청산이 없습니다.';
    if (Number(position?.price ?? 0) <= MARKET_RULES.productPriceFloor) {
      return `현재 ${MARKET_RULES.productPriceFloor}P · 신규 매수 중단, 보유분 매도 가능`;
    }
    const liquidationMove = (100 / product.multiplier).toFixed(product.multiplier === 3 ? 2 : 0);
    const direction = product.positionType === 'inverse' ? '상승' : '하락';
    const price = Number(position?.liquidationPrice ?? 0);
    return `${direction} ${liquidationMove}% 도달 시 전량 청산${price > 0 ? ` · 청산선 ${number.format(price)}P` : ''}`;
  }

  function marketChartMarkup(history, positive) {
    const points = Array.isArray(history) ? history.filter((row) => Number(row?.price) > 0) : [];
    if (!points.length) return '<p>가격 기록 대기 중</p>';
    const values = points.map((row) => Number(row.price));
    const min = Math.min(...values);
    const max = Math.max(...values);
    const spread = Math.max(1, max - min);
    const coords = values.map((value, index) => {
      const x = values.length === 1 ? 320 : 10 + (index / (values.length - 1)) * 620;
      const y = 166 - ((value - min) / spread) * 146;
      return [x, y];
    });
    if (coords.length === 1) coords.push([630, coords[0][1]]);
    const line = coords.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(' ');
    const area = `10,176 ${line} 630,176`;
    return `
      <svg viewBox="0 0 640 180" preserveAspectRatio="none" role="img" aria-label="오늘 시간별 가격 흐름">
        <defs><linearGradient id="marketArea" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-opacity=".28"/><stop offset="1" stop-opacity="0"/></linearGradient></defs>
        <g class="market-chart-grid"><path d="M0 45H640M0 90H640M0 135H640"/></g>
        <polygon class="market-chart-area ${positive ? 'up' : 'down'}" points="${area}"/>
        <polyline class="market-chart-line ${positive ? 'up' : 'down'}" points="${line}"/>
      </svg>
      <div><span>LOW ${number.format(min)}P</span><span>오늘 · 1시간봉</span><span>HIGH ${number.format(max)}P</span></div>
    `;
  }

  function updateMarketOrderSummary() {
    const asset = currentMarketAsset();
    const position = currentMarketPosition(asset);
    const quantity = normalizeMarketQuantity(elements.marketQuantity?.value);
    const gross = position ? Number(position.price) * quantity : 0;
    elements.marketOrderGross.textContent = `${number.format(gross)}P`;
    elements.marketOrderFee.textContent = `${number.format(gross ? marketFee(gross) : 0)}P`;
    const product = currentMarketProduct();
    const buySuspended = product.multiplier >= 2
      && Number(position?.price ?? 0) <= MARKET_RULES.productPriceFloor;
    elements.marketBuyButton.disabled = marketLoading || !asset || !position || !quantity
      || buySuspended || !serverCommands?.marketTrade;
    elements.marketSellButton.disabled = marketLoading || !asset || !position || !quantity
      || quantity > Number(position.quantity ?? 0) || !serverCommands?.marketTrade;
  }

  function renderMarket() {
    hideMiniGamePanels();
    elements.marketShell.hidden = false;
    const state = marketState ?? marketLocalPreview();
    const assets = Array.isArray(state.assets) ? state.assets : [];
    if (!assets.some((asset) => asset.symbol === marketSelectedSymbol) && assets[0]) {
      marketSelectedSymbol = assets[0].symbol;
    }
    const cardById = new Map(cards.map((card) => [card.id, card]));
    elements.marketNextUpdate.textContent = marketCountdownLabel();
    elements.marketAssetList.innerHTML = assets.length ? assets.map((asset) => {
      const card = cardById.get(asset.cardId);
      const change = Number(asset.changeBps ?? 0) / 100;
      const direction = change > 0 ? 'up' : change < 0 ? 'down' : 'flat';
      return `<button type="button" class="market-asset-row ${asset.symbol === marketSelectedSymbol ? 'active' : ''}" data-market-symbol="${escapeHtml(asset.symbol)}">
        <img src="${card ? imagePath(card) : ''}" alt="">
        <span><b>${escapeHtml(asset.name)}</b><small>${escapeHtml(asset.symbol)}</small></span>
        <strong>${number.format(asset.price)}P</strong>
        <em class="${direction}">${change > 0 ? '+' : ''}${change.toFixed(2)}%</em>
      </button>`;
    }).join('') : '<p>시세 동기화 중</p>';

    const asset = currentMarketAsset() ?? assets[0];
    if (asset) {
      const card = cardById.get(asset.cardId);
      const product = currentMarketProduct();
      const position = currentMarketPosition(asset);
      const change = Number(position?.changeBps ?? asset.changeBps ?? 0) / 100;
      elements.marketSelectedImage.src = card ? imagePath(card) : '';
      elements.marketSelectedImage.alt = asset.name;
      elements.marketSelectedSymbol.textContent = asset.symbol;
      elements.marketSelectedName.textContent = asset.name;
      elements.marketSelectedProduct.textContent = marketProductLabel(product.positionType, product.multiplier);
      elements.marketSelectedProduct.dataset.type = product.positionType;
      elements.marketSelectedPrice.textContent = `${number.format(position?.price ?? asset.price)}P`;
      elements.marketSelectedChange.textContent = `${change > 0 ? '+' : ''}${change.toFixed(2)}%`;
      elements.marketSelectedChange.className = change > 0 ? 'up' : change < 0 ? 'down' : 'flat';
      elements.marketChart.innerHTML = marketChartMarkup(position?.history ?? asset.history, change >= 0);
      elements.marketOwnedQuantity.textContent = `${number.format(position?.quantity ?? 0)}주`;
      elements.marketAveragePrice.textContent = `${number.format(position?.averagePrice ?? 0)}P`;
      elements.marketPositionValue.textContent = `${number.format(position?.marketValue ?? 0)}P`;
      elements.marketPositionPnl.textContent = marketSignedPoints(position?.unrealizedPnl);
      elements.marketPositionPnl.className = Number(position?.unrealizedPnl) > 0 ? 'up' : Number(position?.unrealizedPnl) < 0 ? 'down' : '';
      elements.marketProductSelect.value = product.key;
      elements.marketProductRisk.textContent = marketProductRiskText(product, position);
    }

    const invested = Number(state.investedPoints ?? 0);
    const value = Number(state.marketValue ?? 0);
    const unrealized = value - invested;
    const cap = Number(state.totalInvestmentCap ?? MARKET_RULES.totalInvestmentCap);
    elements.marketInvestedPoints.textContent = `${number.format(invested)}P`;
    elements.marketValue.textContent = `${number.format(value)}P`;
    elements.marketUnrealizedPnl.textContent = `${marketSignedPoints(unrealized)} (${marketSignedPercent(marketReturnRate(unrealized, invested))})`;
    elements.marketUnrealizedPnl.className = unrealized > 0 ? 'up' : unrealized < 0 ? 'down' : '';
    elements.marketRealizedPnl.textContent = marketSignedPoints(state.realizedPnl);
    elements.marketRealizedPnl.className = Number(state.realizedPnl) > 0 ? 'up' : Number(state.realizedPnl) < 0 ? 'down' : '';
    elements.marketInvestmentCap.textContent = `${number.format(invested)} / ${number.format(cap)}P`;
    elements.marketInvestmentBar.style.width = `${Math.min(100, invested / Math.max(1, cap) * 100)}%`;

    const trades = Array.isArray(state.recentTrades) ? state.recentTrades : [];
    elements.marketTradeList.innerHTML = trades.length ? trades.map((trade) => `
      <article class="market-trade-row" data-side="${trade.side}">
        <b>${trade.side === 'buy' ? '매수' : trade.side === 'sell' ? '매도' : '청산'}</b>
        <span>${escapeHtml(trade.name ?? trade.symbol)} ${escapeHtml(trade.productLabel ?? marketProductLabel(trade.positionType, trade.multiplier))} · ${number.format(trade.quantity)}주</span>
        <strong>${marketSignedPoints(trade.side === 'liquidation' ? trade.realizedPnl : trade.netPoints)}</strong>
      </article>
    `).join('') : '<p>체결 내역 없음</p>';
    updateMarketOrderSummary();
  }

  async function loadMarketState({ silent = false } = {}) {
    if (marketLoading) return;
    if (!serverCommands?.getMarketState) {
      marketState = marketLocalPreview();
      render();
      return;
    }
    marketLoading = true;
    if (!silent) render();
    const response = await serverCommands.getMarketState();
    marketLoading = false;
    if (response?.ok === false || !Array.isArray(response?.assets)) {
      marketNextSyncAt = clock.now() + 30_000;
      render();
      if (!silent) showToast(response?.message ?? '캄스증권 시세를 불러오지 못했습니다.');
      return;
    }
    marketState = response;
    const nextUpdate = Number(response.nextUpdateAt ?? 0);
    marketNextSyncAt = nextUpdate > clock.now() ? nextUpdate + 1_000 : clock.now() + 5_000;
    render();
  }

  async function submitMarketTrade(side) {
    if (marketLoading || !serverCommands?.marketTrade) return;
    const asset = currentMarketAsset();
    const product = currentMarketProduct();
    const position = currentMarketPosition(asset);
    const quantity = normalizeMarketQuantity(elements.marketQuantity.value);
    if (!asset || !position || !quantity) return showToast('주문 수량을 확인하세요.');
    if (side === 'buy' && product.multiplier >= 2
      && Number(position.price) <= MARKET_RULES.productPriceFloor) {
      return showToast('1P에 도달한 레버리지·인버스 상품은 신규 매수할 수 없습니다.');
    }
    if (side === 'sell' && quantity > Number(position.quantity ?? 0)) return showToast('선택 상품 보유 수량이 부족합니다.');
    marketLoading = true;
    render();
    const response = await serverCommands.marketTrade({
      symbol: asset.symbol,
      side,
      quantity,
      positionType: product.positionType,
      multiplier: product.multiplier,
    });
    marketLoading = false;
    if (response?.ok === false) {
      render();
      return showToast(response.message ?? '매매 주문 처리에 실패했습니다.');
    }
    const result = response.result ?? {};
    showToast(`${asset.name} ${product.label} ${side === 'buy' ? '매수' : '매도'} ${number.format(quantity)}주 체결 · ${number.format(result.unitPrice ?? position.price)}P`);
    await loadMarketState({ silent: true });
  }

  function renderLotto() {
    hideMiniGamePanels();
    elements.lottoShell.hidden = false;

    const round = lottoState?.round;
    const tickets = currentLottoTickets();
    const ticketLimit = Number(lottoState?.ticketLimit ?? LOTTO_RULES.ticketLimit);
    const displayedNumbers = normalizeLottoNumbers(lottoNumbers);
    const selection = new Set(displayedNumbers);
    const locked = lottoLoading || tickets.length >= ticketLimit || !round?.saleOpen;
    // 회차마다 상한이 다를 수 있다(1~18 로 팔린 회차가 아직 남아 있다).
    // 서버가 내려준 값을 우선 쓰고, 없을 때만 설정값으로 떨어진다.
    const maxNumber = currentLottoMaxNumber();
    elements.lottoNumberGrid.innerHTML = Array.from({ length: maxNumber }, (_, index) => {
      const value = index + 1;
      return `<button type="button" data-lotto-number="${value}" class="${selection.has(value) ? 'selected' : ''}" ${locked ? 'disabled' : ''}>${value}</button>`;
    }).join('');
    elements.lottoSelectedNumbers.innerHTML = Array.from({ length: LOTTO_RULES.picks }, (_, index) => (
      displayedNumbers[index] == null ? '<i class="lotto-ball">?</i>' : `<i class="lotto-ball">${displayedNumbers[index]}</i>`
    )).join('');
    elements.lottoAutoPickButton.disabled = locked;

    elements.lottoRoundLabel.textContent = round
      ? `${formatLottoRound(round.drawAt)} 추첨 · ${number.format(round.ticketCount ?? 0)}장`
      : '회차 확인 중';
    elements.lottoSaleStatus.textContent = lottoLoading ? '동기화 중' : round?.saleOpen ? '구매 가능' : '판매 마감';
    elements.lottoSaleStatus.classList.toggle('closed', !round?.saleOpen);
    elements.lottoFirstPool.textContent = `${number.format(round?.firstPool ?? 100_000)} P`;
    elements.lottoSecondPool.textContent = `${number.format(round?.secondPool ?? 50_000)} P`;

    const myRecent = lottoState?.myRecentTickets?.[0] ?? null;
    if (tickets.length) {
      elements.lottoMyTicket.innerHTML = `<div class="lotto-ticket-list">${tickets.map((ticket, index) => `<div class="lotto-ticket-entry"><b>${index + 1}번</b><div class="lotto-inline-balls">${lottoBallMarkup(normalizeLottoNumbers(ticket.numbers))}</div></div>`).join('')}</div><div class="lotto-result-summary"><span>${tickets.length} / ${ticketLimit}장 구매</span><strong>자동 지급 대기</strong></div>`;
    } else if (myRecent) {
      const hits = Array.isArray(myRecent.winningNumbers)
        ? myRecent.numbers.filter((value) => myRecent.winningNumbers.includes(value))
        : [];
      elements.lottoMyTicket.innerHTML = `<div class="lotto-inline-balls">${lottoBallMarkup(myRecent.numbers ?? [], { hits })}</div><div class="lotto-result-summary"><span>${myRecent.matchCount ?? 0}개 일치</span><strong>${myRecent.prizePoints > 0 ? `+${number.format(myRecent.prizePoints)}P 지급` : '꽝'}</strong></div>`;
    } else {
      elements.lottoMyTicket.textContent = '이번 회차 미구매';
    }

    const latest = lottoState?.recentResults?.[0] ?? null;
    elements.lottoLatestResult.innerHTML = latest
      ? `<div class="lotto-inline-balls">${lottoBallMarkup(latest.winningNumbers ?? [])}</div><div class="lotto-result-summary"><span>${formatLottoRound(latest.drawAt)}</span><strong>1등 ${number.format(latest.firstWinners ?? 0)}명 · 2등 ${number.format(latest.secondWinners ?? 0)}명</strong></div>`
      : '추첨 기록 대기 중';

    const winners = lottoState?.recentWinners ?? [];
    elements.lottoWinnerList.classList.toggle('empty', !winners.length);
    elements.lottoWinnerList.innerHTML = winners.length
      ? winners.map((winner) => `<div class="lotto-winner-row"><b>${winner.rank}등</b><span>${escapeHtml(winner.nickname)}</span><strong>${number.format(winner.points)}P</strong></div>`).join('')
      : '아직 1·2등 당첨자가 없습니다.';

    elements.lottoEntryStatus.textContent = lottoLoading
      ? '회차 정보를 불러오는 중입니다.'
      : tickets.length >= ticketLimit
        ? `이번 회차 ${ticketLimit}장 구매 완료 · 자동 지급 대기`
        : !round?.saleOpen
          ? '판매가 마감됐습니다. 추첨 후 다음 회차가 열립니다.'
          : lottoNumbers.length === LOTTO_RULES.picks
            ? `${tickets.length + 1}번째 티켓 번호 선택 완료. 구매를 확정하세요.`
            : `${tickets.length + 1}번째 티켓 번호 ${LOTTO_RULES.picks - lottoNumbers.length}개를 더 선택하세요.`;
    if (elements.lottoHistoryDialog.open) renderLottoHistory();
  }

  function render() {
    renderHeader();
    renderControls();
    if (selectedGame === 'lotto') renderLotto();
    else if (selectedGame === 'arena') renderArena();
    else if (selectedGame === 'market') renderMarket();
    else if (session?.game === 'memory') renderMemory();
    else if (session?.game === 'sumTen') renderSumTen();
    else if (session?.game === 'ladder') renderLadder();
    else if (result) renderResult();
    else renderReady();
    window.lucide?.createIcons();
  }

  function stopTimer() {
    if (timer) window.clearInterval(timer);
    timer = 0;
  }

  function saveResult(game, score, reward) {
    const state = getState();
    const daily = progress();
    daily.plays += 1;
    daily.pointsEarned += reward;
    daily.pointsEarnedByGame[game] += reward;
    if (game === 'memory') daily.bestMemory = Math.max(daily.bestMemory, score);
    else if (game === 'sumTen') daily.bestSumTen = Math.max(daily.bestSumTen, score);
    else daily.bestLadder = Math.max(daily.bestLadder, reward);
    state.points += reward;
    persist('finishMinigame');
  }

  async function finishGame({ completed = false, aborted = false } = {}) {
    if (!session) return;
    if (session.game === 'ladder') {
      if (ladderResolving) return;
      result = { mode: 'reward', score: 0, scoreLabel: '선택 취소', reward: 0, title: '게임 종료' };
      session = null;
      render();
      return;
    }
    stopTimer();
    const finished = session;
    const remainingSeconds = sessionRemaining();
    const rawReward = selectedMode === 'reward' && !aborted ? calculateMiniGameReward(finished.game, {
      completed,
      difficulty: finished.difficulty,
      matches: finished.matches ?? 0,
      remainingSeconds,
      score: finished.score,
    }) : 0;
    let reward = capMiniGameReward(progress(), finished.game, rawReward);
    if (serverCommands && finished.mode === 'reward') {
      const response = await serverCommands.finishMinigame({
        runId: finished.runId,
        inputLog: finished.inputLog,
        score: finished.score,
      });
      if (!response?.ok) {
        session = null;
        render();
        return showToast(response?.message || '요청 처리 실패');
      }
      reward = response.result?.rewardPoints ?? 0;
    } else saveResult(finished.game, finished.score, reward);
    result = {
      mode: finished.mode,
      score: finished.score,
      reward,
      title: aborted ? '게임 종료' : completed ? '퍼즐 완료' : '시간 종료',
    };
    session = null;
    resolvingMemory = false;
    sumDrag = null;
    render();
  }

  function tick() {
    if (!session) return;
    elements.miniGameTimer.textContent = formatTime(sessionRemaining());
    if (sessionRemaining() <= 0) finishGame();
  }

  async function startGame() {
    const state = getState();
    const daily = progress();
    if (selectedGame === 'market') return;
    if (selectedGame === 'lotto') return buyLottoTicket();
    if (selectedGame === 'arena') return startArenaFight();
    if (selectedGame === 'ladder') {
      if ((daily.pointsEarnedByGame.ladder ?? 0) >= MINI_GAME_RULES.dailyPointCapPerGame) {
        return showToast('오늘 운명의 사다리 보상 한도 도달');
      }
      if (state.actionEnergy < MINI_GAME_RULES.ladder.energyCost) return showToast('행동력 100 필요');
      result = null;
      sequence += 1;
      session = { id: sequence, game: 'ladder', mode: 'reward', phase: 'choose', score: 0, startLane: null, board: null };
      render();
      return;
    }
    if (selectedMode === 'reward') {
      if ((daily.pointsEarnedByGame[selectedGame] ?? 0) >= MINI_GAME_RULES.dailyPointCapPerGame) {
        return showToast(`오늘 ${selectedGame === 'memory' ? '카드 짝맞추기' : MINI_GAME_RULES.sumTen.label} 보상 한도 도달`);
      }
      if (state.actionEnergy < MINI_GAME_RULES.energyCost) return showToast('행동력 부족');
      if (!serverCommands) {
        state.actionEnergy -= MINI_GAME_RULES.energyCost;
        state.lastEnergyAt = clock.now();
        persist('startMinigame');
      }
    }
    result = null;
    sequence += 1;
    const now = clock.now();
    const seed = `${now}:${sequence}:${selectedGame}:${memoryDifficulty}`;
    if (serverCommands && selectedMode === 'reward') {
      const response = await serverCommands.startMinigame({
        game: selectedGame,
        difficulty: selectedGame === 'memory' ? memoryDifficulty : null,
      });
      if (!response?.ok) return showToast('미니게임 시작 실패: ' + (response?.message || response?.code || '알 수 없음'));
      const remote = response.result;
      if (selectedGame === 'memory') {
        const cardsById = new Map(cards.map((card) => [card.id, card]));
        const started = clock.now();
        session = {
          id: sequence, runId: remote.runId, inputLog: [], game: 'memory', mode: selectedMode,
          difficulty: memoryDifficulty, columns: memoryDifficulty === 'advanced' ? 6 : 4,
          pairs: remote.board.length / 2,
          deck: remote.board.map((cardId) => ({ ...cardsById.get(cardId), pairId: cardId })),
          startAt: started, endAt: started + remote.timeLimit * 1000,
          open: [], matched: new Set(), matches: 0, attempts: 0, streak: 0, score: 0,
        };
      } else {
        const started = clock.now();
        session = {
          id: sequence, runId: remote.runId, inputLog: [], game: 'sumTen', mode: selectedMode,
          columns: 17, rows: 10,
          tiles: remote.board.map((value, index) => ({ index, value, row: Math.floor(index / 17), column: index % 17, active: true })),
          startAt: started, endAt: started + remote.timeLimit * 1000, score: 0, combinations: 0,
        };
      }
    } else if (selectedGame === 'memory') {
      const created = createMemoryDeck(cards, memoryDifficulty, seed);
      session = {
        id: sequence, game: 'memory', mode: selectedMode, difficulty: memoryDifficulty,
        ...created, startAt: now, endAt: now + created.timeLimit * 1000,
        open: [], matched: new Set(), matches: 0, attempts: 0, streak: 0, score: 0,
      };
    } else {
      const created = createSumTenBoard(seed);
      session = {
        id: sequence, game: 'sumTen', mode: selectedMode,
        ...created, startAt: now, endAt: now + created.timeLimit * 1000,
        score: 0, combinations: 0,
      };
    }
    // Initial deadlock guard (mirrors server): reshuffle a dead board, else play as dealt.
    if (session?.game === 'sumTen') ensureSumPlayable();
    render();
    stopTimer();
    timer = window.setInterval(tick, 1000);
  }

  async function loadLottoState({ silent = false } = {}) {
    if (!serverCommands?.getLottoState || lottoLoading) return;
    lottoLoading = true;
    const requestId = ++lottoRequestSequence;
    if (!silent) render();
    const response = await serverCommands.getLottoState();
    if (requestId !== lottoRequestSequence) return;
    lottoLoading = false;
    if (!response?.ok && !response?.round) {
      lottoNextSyncAt = clock.now() + 30_000;
      render();
      if (!silent) showToast(response?.message || '로또 정보를 불러오지 못했습니다.');
      return;
    }
    lottoState = response;
    const drawAt = Number(response.round?.drawAt ?? 0);
    const nearDraw = drawAt > 0 && Math.abs(drawAt - clock.now()) <= 120_000;
    lottoNextSyncAt = clock.now() + (nearDraw ? 15_000 : 60_000);
    if (
      Number.isSafeInteger(response.playerRevision)
      && response.playerRevision > Number(getState().revision ?? 0)
      && serverCommands.refreshSnapshot
    ) {
      await serverCommands.refreshSnapshot();
    }
    render();
  }

  async function buyLottoTicket() {
    if (lottoLoading || !serverCommands?.buyLottoTicket) return;
    const picked = normalizeLottoNumbers(lottoNumbers);
    if (picked.length !== LOTTO_RULES.picks) return showToast(`1~${currentLottoMaxNumber()} 중 서로 다른 번호 6개를 선택하세요.`);
    if (!lottoState?.round?.saleOpen) return showToast('이번 회차 판매가 마감됐습니다.');
    if (currentLottoTickets().length >= LOTTO_RULES.ticketLimit) return showToast('이번 회차 로또 2장을 모두 구매했습니다.');
    if (getState().points < LOTTO_RULES.ticketCost) return showToast('로또 구매에 1,000P가 필요합니다.');
    lottoLoading = true;
    render();
    const response = await serverCommands.buyLottoTicket({ numbers: picked });
    lottoLoading = false;
    if (!response?.ok) {
      render();
      return showToast(response?.message || '로또 구매에 실패했습니다.');
    }
    lottoNumbers = [];
    showToast(`로또 구매 완료 · ${picked.join(', ')}`);
    await loadLottoState({ silent: true });
  }

  function renderLottoHistory() {
    const history = Array.isArray(lottoState?.history) ? lottoState.history : [];
    elements.lottoHistoryList.innerHTML = history.length
      ? history.map((draw) => `
        <article class="lotto-history-row">
          <time>${formatLottoRound(draw.drawAt)}</time>
          <div>${lottoBallMarkup(draw.winningNumbers ?? [])}</div>
          <small>1등 ${number.format(draw.firstWinners ?? 0)}명 · 2등 ${number.format(draw.secondWinners ?? 0)}명</small>
        </article>
      `).join('')
      : `<p>${lottoLoading ? '당첨번호 기록을 동기화하는 중입니다.' : '최근 7일간 완료된 추첨이 없습니다.'}</p>`;
  }

  function openLottoHistory() {
    if (!elements.lottoHistoryDialog.open) elements.lottoHistoryDialog.showModal();
    renderLottoHistory();
  }

  function toggleLottoNumber(value) {
    if (selectedGame !== 'lotto' || lottoLoading || currentLottoTickets().length >= LOTTO_RULES.ticketLimit || !lottoState?.round?.saleOpen) return;
    if (!Number.isInteger(value) || value < 1 || value > currentLottoMaxNumber()) return;
    if (lottoNumbers.includes(value)) lottoNumbers = lottoNumbers.filter((numberValue) => numberValue !== value);
    else if (lottoNumbers.length < LOTTO_RULES.picks) lottoNumbers = [...lottoNumbers, value].sort((left, right) => left - right);
    else return showToast('번호는 6개까지 선택할 수 있습니다.');
    render();
  }

  function autoPickLottoNumbers() {
    if (selectedGame !== 'lotto' || lottoLoading || currentLottoTickets().length >= LOTTO_RULES.ticketLimit || !lottoState?.round?.saleOpen) return;
    lottoNumbers = pickRandomLottoNumbers(random, currentLottoMaxNumber());
    render();
    showToast(`자동 선택 · ${lottoNumbers.join(', ')}`);
  }

  function heartbeat() {
    if (selectedGame === 'lotto') {
      elements.miniGameTimer.textContent = lottoCountdownLabel();
      if (clock.now() >= lottoNextSyncAt) void loadLottoState({ silent: true });
    } else if (selectedGame === 'market') {
      const countdown = marketCountdownLabel();
      elements.miniGameTimer.textContent = countdown;
      elements.marketNextUpdate.textContent = countdown;
      if (clock.now() >= marketNextSyncAt) void loadMarketState({ silent: true });
    }
  }

  async function chooseLadderLane(lane) {
    if (!session || session.game !== 'ladder' || session.phase !== 'choose' || ladderResolving) return;
    if (!Number.isInteger(lane) || lane < 0 || lane >= MINI_GAME_RULES.ladder.columns) return;
    if ((progress().pointsEarnedByGame.ladder ?? 0) >= MINI_GAME_RULES.dailyPointCapPerGame) {
      session = null;
      render();
      return showToast('오늘 운명의 사다리 보상 한도 도달');
    }
    if (getState().actionEnergy < MINI_GAME_RULES.ladder.energyCost) return showToast('행동력 100 필요');
    const sessionId = session.id;
    ladderResolving = true;
    session.phase = 'resolving';
    session.startLane = lane;
    render();

    let reward;
    let rolledReward;
    let seed;
    if (serverCommands?.playLadder) {
      const response = await serverCommands.playLadder({ lane });
      if (!response?.ok) {
        if (session?.id === sessionId) {
          if ((progress().pointsEarnedByGame.ladder ?? 0) >= MINI_GAME_RULES.dailyPointCapPerGame) session = null;
          else {
            session.phase = 'choose';
            session.startLane = null;
          }
        }
        ladderResolving = false;
        render();
        return showToast(response?.message || '사다리 요청 처리 실패');
      }
      reward = Number(response.result?.rewardPoints ?? 0);
      rolledReward = Number(response.result?.rolledRewardPoints ?? reward);
      seed = response.serverSeed ?? response.result?.serverSeed ?? `${clock.now()}:${sessionId}`;
    } else {
      rolledReward = pickLadderReward(random());
      reward = capMiniGameReward(progress(), 'ladder', rolledReward);
      seed = `${clock.now()}:${sessionId}:${lane}:${rolledReward}`;
      const state = getState();
      state.actionEnergy -= MINI_GAME_RULES.ladder.energyCost;
      state.lastEnergyAt = clock.now();
      saveResult('ladder', reward, reward);
    }
    if (!session || session.id !== sessionId) return;
    session.reward = reward;
    session.rolledReward = rolledReward;
    session.score = reward;
    session.board = createLadderBoard(seed, lane, rolledReward);
    render();

    const token = document.getElementById('ladderToken');
    for (const point of session.board.path.slice(1)) {
      await wait(point.row === session.board.rungRows ? 180 : 135);
      if (!session || session.id !== sessionId) return;
      token?.style.setProperty('--x', ladderX(point.lane, session.board.columns));
      token?.style.setProperty('--y', point.row === session.board.rungRows ? '100%' : ladderY(point.row, session.board.rungRows));
    }
    session.phase = 'resolved';
    ladderResolving = false;
    render();
    await wait(850);
    if (!session || session.id !== sessionId) return;
    result = {
      mode: 'reward',
      score: reward,
      scoreLabel: rolledReward > reward ? `${lane + 1}번 경로 · 일일 한도 적용` : `${lane + 1}번 경로`,
      reward,
      title: '사다리 당첨',
    };
    session = null;
    render();
    showToast(`사다리 보상 +${number.format(reward)}P`);
  }

  function flipMemoryCard(index) {
    if (!session || session.game !== 'memory' || resolvingMemory || session.matched.has(index) || session.open.includes(index)) return;
    const atMs = Math.floor(Math.max(0, clock.now() - session.startAt));
    if (atMs > session.timeLimit * 1000) return;
    session.open.push(index);
    // 서버 gacha_s2_verify_memory_log 는 각 flip 을 {index, atMs} 단위 액션으로 기대.
    // 매치 1회 = 첫 flip 액션 + 둘째 flip 액션(2개). sumTen 의 {start,end,atMs} 와 다름.
    session.inputLog?.push({ index, atMs });
    renderMemory();
    if (session.open.length < 2) return;
    resolvingMemory = true;
    session.attempts += 1;
    const [left, right] = session.open;
    const matched = session.deck[left].pairId === session.deck[right].pairId;
    const sessionId = session.id;
    window.setTimeout(() => {
      if (!session || session.id !== sessionId) return;
      if (matched) {
        session.matched.add(left);
        session.matched.add(right);
        session.matches += 1;
        session.streak += 1;
        session.score += 100 + session.streak * 20;
      } else {
        session.streak = 0;
        session.score = Math.max(0, session.score - 10);
      }
      session.open = [];
      resolvingMemory = false;
      elements.miniGameScore.textContent = number.format(session.score);
      if (session.matches >= session.pairs) finishGame({ completed: true });
      else renderMemory();
    }, matched ? 320 : 650);
  }

  function sumTileFromPoint(event) {
    const element = document.elementFromPoint(event.clientX, event.clientY)?.closest('[data-sum-index]');
    if (!element || !elements.sumTenBoard.contains(element)) return null;
    return session?.tiles[Number(element.dataset.sumIndex)] ?? null;
  }

  function currentSumEvaluation() {
    if (!session || !sumDrag) return null;
    return evaluateSumSelection(session.tiles, session.columns, sumDrag.start, sumDrag.end);
  }

  function updateSumSelection() {
    const evaluation = currentSumEvaluation();
    if (!evaluation) return;
    const selected = new Set(evaluation.indices);
    elements.sumTenBoard.querySelectorAll('[data-sum-index]').forEach((tile) => {
      tile.classList.toggle('selected', selected.has(Number(tile.dataset.sumIndex)));
    });
    elements.miniGameSelectionSum.textContent = evaluation.sum;
    elements.miniGameSelectionSum.parentElement.classList.toggle('invalid', evaluation.sum > 10);
  }

  function beginSumDrag(event) {
    if (!session || session.game !== 'sumTen') return;
    const tile = sumTileFromPoint(event);
    if (!tile) return;
    event.preventDefault();
    sumDrag = { pointerId: event.pointerId, start: tile, end: tile };
    elements.sumTenBoard.setPointerCapture?.(event.pointerId);
    updateSumSelection();
  }

  function moveSumDrag(event) {
    if (!sumDrag || event.pointerId !== sumDrag.pointerId) return;
    const tile = sumTileFromPoint(event);
    if (!tile || tile.index === sumDrag.end.index) return;
    sumDrag.end = tile;
    updateSumSelection();
  }

  function endSumDrag(event) {
    if (!sumDrag || event.pointerId !== sumDrag.pointerId || !session) return;
    const maxMs = session.endAt - session.startAt;
    const atMs = Math.floor(Math.min(maxMs, Math.max(0, clock.now() - session.startAt)));
    const evaluation = currentSumEvaluation();
    if (evaluation?.valid) {
      session.inputLog?.push({
        start: sumDrag.start.index,
        end: sumDrag.end.index,
        atMs,
      });
      session.tiles = applySumSelection(session.tiles, evaluation);
      session.score += evaluation.count;
      session.combinations += 1;
      elements.miniGameScore.textContent = number.format(session.score);
    }
    sumDrag = null;
    if (session.tiles.every((tile) => !tile.active)) return finishGame({ completed: true });
    if (!ensureSumPlayable()) return finishGame({ completed: false });
    renderSumTen();
  }

  // When the board deadlocks (no sum-10 remains) reshuffle the leftover tiles in
  // place. Returns false only when no arrangement can restore a move — the server
  // verify RPC runs the identical check, so both sides stay in sync.
  function ensureSumPlayable() {
    if (!session || session.game !== 'sumTen') return true;
    if (!session.tiles.some((tile) => tile.active)) return true;
    if (hasValidSumMove(session.tiles, session.columns, session.rows)) return true;
    const next = reshuffleSumTiles(session.tiles, session.columns, session.rows);
    if (!next) return false;
    session.tiles = next;
    session.reshuffles = (session.reshuffles ?? 0) + 1;
    showToast('재배치! 합계 10 조합이 새로 생겼어요');
    return true;
  }

  elements.miniGamePicker.addEventListener('click', (event) => {
    const button = event.target.closest('[data-minigame-select]');
    if (!button || session) return;
    selectedGame = button.dataset.minigameSelect;
    // 연습 모드로 두고 투기장에 들어오면 토글이 숨겨진 채 값만 남는다. 보상으로 되돌린다.
    if (selectedGame === 'arena') selectedMode = 'reward';
    if (selectedGame === 'market') selectedMode = 'reward';
    result = null;
    render();
    if (selectedGame === 'lotto') void loadLottoState();
    if (selectedGame === 'arena') void loadArenaState();
    else {
      clearArenaBattleTimers();
      if (elements.arenaBattleDialog?.open) elements.arenaBattleDialog.close();
    }
    if (selectedGame === 'market') void loadMarketState();
  });
  elements.miniGameMode.addEventListener('click', (event) => {
    const button = event.target.closest('[data-mini-mode]');
    if (!button || session) return;
    selectedMode = button.dataset.miniMode;
    result = null;
    render();
  });
  elements.miniGameDifficulty.addEventListener('click', (event) => {
    const button = event.target.closest('[data-memory-difficulty]');
    if (!button || session) return;
    memoryDifficulty = button.dataset.memoryDifficulty;
    result = null;
    render();
  });
  elements.miniGameStartButton.addEventListener('click', startGame);
  elements.miniGameStopButton.addEventListener('click', () => finishGame({ aborted: true }));
  elements.memoryBoard.addEventListener('click', (event) => {
    const button = event.target.closest('[data-memory-index]');
    if (button) flipMemoryCard(Number(button.dataset.memoryIndex));
  });
  elements.sumTenBoard.addEventListener('pointerdown', beginSumDrag);
  elements.sumTenBoard.addEventListener('pointermove', moveSumDrag);
  elements.sumTenBoard.addEventListener('pointerup', endSumDrag);
  elements.sumTenBoard.addEventListener('pointercancel', endSumDrag);
  elements.ladderBoard.addEventListener('click', (event) => {
    const button = event.target.closest('[data-ladder-lane]');
    if (button) chooseLadderLane(Number(button.dataset.ladderLane));
  });
  elements.lottoNumberGrid.addEventListener('click', (event) => {
    const button = event.target.closest('[data-lotto-number]');
    if (button) toggleLottoNumber(Number(button.dataset.lottoNumber));
  });
  elements.lottoAutoPickButton.addEventListener('click', autoPickLottoNumbers);
  elements.lottoHistoryButton.addEventListener('click', () => {
    openLottoHistory();
  });
  elements.marketAssetList?.addEventListener('click', (event) => {
    const button = event.target.closest('[data-market-symbol]');
    if (!button || marketLoading) return;
    marketSelectedSymbol = button.dataset.marketSymbol;
    elements.marketQuantity.value = '1';
    render();
  });
  elements.marketQuantity?.addEventListener('input', updateMarketOrderSummary);
  elements.marketProductSelect?.addEventListener('change', () => {
    marketSelectedProductKey = elements.marketProductSelect.value;
    elements.marketQuantity.value = '1';
    render();
  });
  elements.marketMaxBuy?.addEventListener('click', () => {
    const asset = currentMarketAsset();
    const position = currentMarketPosition(asset);
    if (!asset || !position) return;
    const totalRemaining = Math.max(0, Number(marketState?.totalInvestmentCap ?? MARKET_RULES.totalInvestmentCap) - Number(marketState?.investedPoints ?? 0));
    const assetRemaining = Math.max(0, Number(marketState?.perAssetInvestmentCap ?? MARKET_RULES.perAssetInvestmentCap) - Number(asset.investedPoints ?? asset.costBasis ?? 0));
    const available = Math.min(Number(getState().points ?? 0), totalRemaining, assetRemaining);
    let quantity = Math.max(0, Math.floor(available / (Number(position.price) * (1 + MARKET_RULES.feeRate))));
    while (quantity > 0 && Number(position.price) * quantity + marketFee(Number(position.price) * quantity) > available) quantity -= 1;
    elements.marketQuantity.value = String(Math.max(1, quantity));
    updateMarketOrderSummary();
    if (!quantity) showToast('현재 한도와 포인트로 매수 가능한 수량이 없습니다.');
  });
  elements.marketMaxSell?.addEventListener('click', () => {
    const quantity = Number(currentMarketPosition()?.quantity ?? 0);
    elements.marketQuantity.value = String(Math.max(1, quantity));
    updateMarketOrderSummary();
    if (!quantity) showToast('매도할 보유 주식이 없습니다.');
  });
  elements.marketBuyButton?.addEventListener('click', () => submitMarketTrade('buy'));
  elements.marketSellButton?.addEventListener('click', () => submitMarketTrade('sell'));
  // 연출 도중 누르면 결과로 건너뛰고, 결과가 떠 있으면 닫는다.
  elements.arenaBattleStage?.addEventListener('click', (event) => {
    if (event.target.closest('#arenaBattleClose')) return;
    if (arenaBattleSkip) arenaBattleSkip();
  });
  elements.arenaBattleClose?.addEventListener('click', () => {
    clearArenaBattleTimers();
    arenaBattleSkip = null;
    elements.arenaBattleDialog?.close();
  });
  // ESC 로 닫아도 남은 타이머가 돌면 안 된다.
  elements.arenaBattleDialog?.addEventListener('close', () => {
    clearArenaBattleTimers();
    arenaBattleSkip = null;
  });
  elements.arenaRankingButton?.addEventListener('click', () => {
    renderArenaRanking();
    elements.arenaRankingDialog?.showModal();
    window.lucide?.createIcons();
  });

  progress();
  return { render, tick, heartbeat };
}
