import { RARITIES } from './config.js';
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
} from './lotto.js';

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
    'lottoShell', 'lottoRoundLabel', 'lottoSaleStatus', 'lottoNumberGrid',
    'lottoSelectedNumbers', 'lottoMyTicket', 'lottoLatestResult', 'lottoWinnerList',
    'lottoControl', 'lottoFirstPool', 'lottoSecondPool', 'lottoEntryStatus',
    'lottoHistoryButton', 'lottoHistoryDialog', 'lottoHistoryList',
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
    elements.miniGameEyebrow.textContent = memory ? 'MEMORY SIGNAL' : ladder ? 'LUCKY LADDER' : lotto ? 'LOTTO 6/18' : 'CAMMON APPLE';
    elements.miniGameTitle.textContent = memory ? '카드 짝맞추기' : ladder ? MINI_GAME_RULES.ladder.label : lotto ? '시그널 로또' : MINI_GAME_RULES.sumTen.label;
    elements.miniGameTimer.textContent = lotto ? lottoCountdownLabel() : ladder ? '--:--' : formatTime(session ? sessionRemaining() : (
      memory ? MINI_GAME_RULES.memory[memoryDifficulty].timeLimit : MINI_GAME_RULES.sumTen.timeLimit
    ));
    elements.miniGameScore.textContent = lotto
      ? `${lottoState?.ticket?.numbers?.length ?? lottoNumbers.length} / ${LOTTO_RULES.picks}`
      : number.format(currentScore());
  }

  function renderControls() {
    const daily = progress();
    const ladder = selectedGame === 'ladder';
    const lotto = selectedGame === 'lotto';
    const earned = daily.pointsEarnedByGame[selectedGame] ?? 0;
    const remaining = Math.max(0, MINI_GAME_RULES.dailyPointCapPerGame - earned);
    const busy = Boolean(session);
    const energyCost = ladder ? MINI_GAME_RULES.ladder.energyCost : MINI_GAME_RULES.energyCost;
    elements.miniGameDailyBlock.hidden = lotto;
    elements.miniGameMode.hidden = lotto;
    elements.miniGameRecords.hidden = lotto;
    elements.lottoControl.hidden = !lotto;
    elements.miniGameControlEyebrow.textContent = lotto ? 'DRAW CONTROL' : 'PLAY MODE';
    elements.miniGameControlTitle.textContent = lotto ? '구매 정보' : '작전 설정';
    if (!lotto) {
      elements.miniGameDaily.textContent = `${number.format(earned)} / ${number.format(MINI_GAME_RULES.dailyPointCapPerGame)} P`;
      elements.miniGameDailyBar.style.width = `${Math.min(100, earned / MINI_GAME_RULES.dailyPointCapPerGame * 100)}%`;
    }
    elements.miniGameBest.textContent = number.format(selectedGame === 'memory' ? daily.bestMemory : ladder ? daily.bestLadder : daily.bestSumTen);
    elements.miniGamePlays.textContent = `${number.format(daily.plays)}회`;
    elements.miniGameRemaining.textContent = `${number.format(remaining)} P`;
    elements.miniGameDifficulty.hidden = selectedGame !== 'memory' || lotto;
    elements.miniGameMode.hidden = lotto || ladder;
    elements.miniGameStartButton.hidden = busy;
    elements.miniGameStopButton.hidden = !busy;
    elements.miniGameStopButton.disabled = ladderResolving;
    elements.miniGameStartButton.disabled = lotto
      ? lottoLoading
        || !lottoState?.round?.saleOpen
        || Boolean(lottoState?.ticket)
        || normalizeLottoNumbers(lottoNumbers).length !== LOTTO_RULES.picks
        || getState().points < LOTTO_RULES.ticketCost
      : (ladder || selectedMode === 'reward')
      && (getState().actionEnergy < energyCost || remaining <= 0);
    elements.miniGameStartButton.querySelector('span').textContent = lotto
      ? lottoState?.ticket ? '이번 회차 구매 완료' : '1,000P 구매 확정'
      : ladder ? '출발점 선택하기' : selectedMode === 'reward' ? '보상 게임 시작' : '연습 시작';
    elements.miniGameStartButton.dataset.mode = lotto || ladder ? 'reward' : selectedMode;
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

  function renderReady() {
    const rules = MINI_GAME_RULES.memory[memoryDifficulty];
    const ladder = selectedGame === 'ladder';
    const previewCard = cards.find((card) => card.id === 'kimyunhwan-2') ?? cards.find((card) => card.rarity !== 'EX');
    elements.miniGameEmpty.hidden = false;
    elements.memoryBoard.hidden = true;
    elements.sumTenShell.hidden = true;
    elements.ladderShell.hidden = true;
    elements.lottoShell.hidden = true;
    elements.miniGameResult.hidden = true;
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
    elements.miniGameEmpty.hidden = true;
    elements.memoryBoard.hidden = true;
    elements.sumTenShell.hidden = true;
    elements.ladderShell.hidden = true;
    elements.lottoShell.hidden = true;
    elements.miniGameResult.hidden = false;
    elements.miniGameResultTitle.textContent = result.title;
    elements.miniGameResultScore.textContent = result.scoreLabel ?? `${number.format(result.score)} SCORE`;
    elements.miniGameResultReward.textContent = result.mode === 'practice' ? 'PRACTICE' : `+${number.format(result.reward)} P`;
  }

  function renderMemory() {
    elements.miniGameEmpty.hidden = true;
    elements.miniGameResult.hidden = true;
    elements.sumTenShell.hidden = true;
    elements.ladderShell.hidden = true;
    elements.lottoShell.hidden = true;
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
    elements.miniGameEmpty.hidden = true;
    elements.miniGameResult.hidden = true;
    elements.memoryBoard.hidden = true;
    elements.ladderShell.hidden = true;
    elements.lottoShell.hidden = true;
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
    elements.miniGameEmpty.hidden = true;
    elements.miniGameResult.hidden = true;
    elements.memoryBoard.hidden = true;
    elements.sumTenShell.hidden = true;
    elements.lottoShell.hidden = true;
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

  function renderLotto() {
    elements.miniGameEmpty.hidden = true;
    elements.miniGameResult.hidden = true;
    elements.memoryBoard.hidden = true;
    elements.sumTenShell.hidden = true;
    elements.ladderShell.hidden = true;
    elements.lottoShell.hidden = false;

    const round = lottoState?.round;
    const ticketNumbers = normalizeLottoNumbers(lottoState?.ticket?.numbers);
    const displayedNumbers = ticketNumbers.length ? ticketNumbers : normalizeLottoNumbers(lottoNumbers);
    const selection = new Set(displayedNumbers.length ? displayedNumbers : lottoNumbers);
    const locked = lottoLoading || Boolean(ticketNumbers.length) || !round?.saleOpen;
    elements.lottoNumberGrid.innerHTML = Array.from({ length: LOTTO_RULES.maximumNumber }, (_, index) => {
      const value = index + 1;
      return `<button type="button" data-lotto-number="${value}" class="${selection.has(value) ? 'selected' : ''}" ${locked ? 'disabled' : ''}>${value}</button>`;
    }).join('');
    elements.lottoSelectedNumbers.innerHTML = Array.from({ length: LOTTO_RULES.picks }, (_, index) => (
      displayedNumbers[index] == null ? '<i class="lotto-ball">?</i>' : `<i class="lotto-ball">${displayedNumbers[index]}</i>`
    )).join('');

    elements.lottoRoundLabel.textContent = round
      ? `${formatLottoRound(round.drawAt)} 추첨 · ${number.format(round.ticketCount ?? 0)}장`
      : '회차 확인 중';
    elements.lottoSaleStatus.textContent = lottoLoading ? '동기화 중' : round?.saleOpen ? '구매 가능' : '판매 마감';
    elements.lottoSaleStatus.classList.toggle('closed', !round?.saleOpen);
    elements.lottoFirstPool.textContent = `${number.format(round?.firstPool ?? 100_000)} P`;
    elements.lottoSecondPool.textContent = `${number.format(round?.secondPool ?? 50_000)} P`;

    const myRecent = lottoState?.myRecentTickets?.[0] ?? null;
    if (ticketNumbers.length) {
      elements.lottoMyTicket.innerHTML = `<div class="lotto-inline-balls">${lottoBallMarkup(ticketNumbers)}</div><div class="lotto-result-summary"><span>구매 완료</span><strong>자동 지급 대기</strong></div>`;
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
    elements.lottoWinnerList.innerHTML = winners.length
      ? winners.map((winner) => `<div class="lotto-winner-row"><b>${winner.rank}등</b><span>${escapeHtml(winner.nickname)}</span><strong>${number.format(winner.points)}P</strong></div>`).join('')
      : '아직 1·2등 당첨자가 없습니다.';

    elements.lottoEntryStatus.textContent = lottoLoading
      ? '회차 정보를 불러오는 중입니다.'
      : ticketNumbers.length
        ? `번호 ${ticketNumbers.join(', ')} · 자동 지급 대기`
        : !round?.saleOpen
          ? '판매가 마감됐습니다. 추첨 후 다음 회차가 열립니다.'
          : lottoNumbers.length === LOTTO_RULES.picks
            ? '번호 선택 완료. 구매를 확정하세요.'
            : `번호 ${LOTTO_RULES.picks - lottoNumbers.length}개를 더 선택하세요.`;
    if (elements.lottoHistoryDialog.open) renderLottoHistory();
  }

  function render() {
    renderHeader();
    renderControls();
    if (selectedGame === 'lotto') renderLotto();
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
    if (selectedGame === 'lotto') return buyLottoTicket();
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
      lottoNextSyncAt = clock.now() + 15_000;
      render();
      if (!silent) showToast(response?.message || '로또 정보를 불러오지 못했습니다.');
      return;
    }
    lottoState = response;
    lottoNextSyncAt = clock.now() + 30_000;
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
    if (picked.length !== LOTTO_RULES.picks) return showToast('1~18 중 서로 다른 번호 6개를 선택하세요.');
    if (!lottoState?.round?.saleOpen) return showToast('이번 회차 판매가 마감됐습니다.');
    if (lottoState.ticket) return showToast('이번 회차 로또는 이미 구매했습니다.');
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
    if (selectedGame !== 'lotto' || lottoLoading || lottoState?.ticket || !lottoState?.round?.saleOpen) return;
    if (!Number.isInteger(value) || value < 1 || value > LOTTO_RULES.maximumNumber) return;
    if (lottoNumbers.includes(value)) lottoNumbers = lottoNumbers.filter((numberValue) => numberValue !== value);
    else if (lottoNumbers.length < LOTTO_RULES.picks) lottoNumbers = [...lottoNumbers, value].sort((left, right) => left - right);
    else return showToast('번호는 6개까지 선택할 수 있습니다.');
    render();
  }

  function heartbeat() {
    if (selectedGame !== 'lotto') return;
    elements.miniGameTimer.textContent = lottoCountdownLabel();
    if (clock.now() >= lottoNextSyncAt) void loadLottoState({ silent: true });
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
    result = null;
    render();
    if (selectedGame === 'lotto') void loadLottoState();
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
  elements.lottoHistoryButton.addEventListener('click', () => {
    openLottoHistory();
  });

  progress();
  return { render, tick, heartbeat };
}
