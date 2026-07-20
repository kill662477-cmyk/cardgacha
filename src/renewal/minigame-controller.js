import { RARITIES } from './config.js';
import {
  MINI_GAME_RULES,
  applySumSelection,
  calculateMiniGameReward,
  capMiniGameReward,
  createMemoryDeck,
  createSumTenBoard,
  evaluateSumSelection,
  hasValidSumMove,
  normalizeMiniGameProgress,
  reshuffleSumTiles,
} from './minigames.js';

const number = new Intl.NumberFormat('ko-KR');

function formatTime(seconds) {
  const value = Math.max(0, Math.ceil(seconds));
  return `${String(Math.floor(value / 60)).padStart(2, '0')}:${String(value % 60).padStart(2, '0')}`;
}

function imagePath(card) {
  return `assets/cards/${encodeURIComponent(card.file)}`;
}

export function createMiniGameController({ cards, getState, persist, showToast, clock, serverCommands = null }) {
  const elements = Object.fromEntries([
    'minigameScreen', 'miniGamePicker', 'miniGameDaily', 'miniGameDailyBar',
    'miniGameEyebrow', 'miniGameTitle', 'miniGameTimer', 'miniGameScore',
    'miniGameStage', 'miniGameEmpty', 'miniGameReadyVisual', 'miniGameReadyTitle',
    'miniGameReadyCopy', 'miniGameReadyMode', 'miniGameStatus', 'memoryBoard', 'sumTenShell',
    'sumTenBoard', 'miniGameSelectionSum', 'miniGameResult', 'miniGameResultTitle',
    'miniGameResultScore', 'miniGameResultReward', 'miniGameMode', 'miniGameDifficulty',
    'miniGameBest', 'miniGamePlays', 'miniGameRemaining', 'miniGameStartButton',
    'miniGameStopButton',
  ].map((id) => [id, document.getElementById(id)]));

  let selectedGame = 'memory';
  let selectedMode = 'reward';
  let memoryDifficulty = 'basic';
  let session = null;
  let timer = 0;
  let resolvingMemory = false;
  let sumDrag = null;
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
    elements.miniGameEyebrow.textContent = memory ? 'MEMORY SIGNAL' : 'CAMMON APPLE';
    elements.miniGameTitle.textContent = memory ? '카드 짝맞추기' : MINI_GAME_RULES.sumTen.label;
    elements.miniGameTimer.textContent = formatTime(session ? sessionRemaining() : (
      memory ? MINI_GAME_RULES.memory[memoryDifficulty].timeLimit : MINI_GAME_RULES.sumTen.timeLimit
    ));
    elements.miniGameScore.textContent = number.format(currentScore());
  }

  function renderControls() {
    const daily = progress();
    const earned = daily.pointsEarnedByGame[selectedGame] ?? 0;
    const remaining = Math.max(0, MINI_GAME_RULES.dailyPointCapPerGame - earned);
    const busy = Boolean(session);
    elements.miniGameDaily.textContent = `${number.format(earned)} / ${number.format(MINI_GAME_RULES.dailyPointCapPerGame)} P`;
    elements.miniGameDailyBar.style.width = `${earned / MINI_GAME_RULES.dailyPointCapPerGame * 100}%`;
    elements.miniGameBest.textContent = number.format(selectedGame === 'memory' ? daily.bestMemory : daily.bestSumTen);
    elements.miniGamePlays.textContent = `${number.format(daily.plays)}회`;
    elements.miniGameRemaining.textContent = `${number.format(remaining)} P`;
    elements.miniGameDifficulty.hidden = selectedGame !== 'memory';
    elements.miniGameStartButton.hidden = busy;
    elements.miniGameStopButton.hidden = !busy;
    elements.miniGameStartButton.disabled = selectedMode === 'reward' && (
      getState().actionEnergy < MINI_GAME_RULES.energyCost || remaining <= 0
    );
    elements.miniGameStartButton.querySelector('span').textContent = selectedMode === 'reward' ? '보상 게임 시작' : '연습 시작';
    elements.miniGameStartButton.dataset.mode = selectedMode;
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
    const previewCard = cards.find((card) => card.id === 'kimyunhwan-2') ?? cards.find((card) => card.rarity !== 'EX');
    elements.miniGameEmpty.hidden = false;
    elements.memoryBoard.hidden = true;
    elements.sumTenShell.hidden = true;
    elements.miniGameResult.hidden = true;
    elements.miniGameReadyVisual.dataset.game = selectedGame;
    elements.miniGameReadyVisual.innerHTML = selectedGame === 'memory'
      ? `<div class="memory-ready-preview"><i class="back"></i><figure style="--rarity:${RARITIES[previewCard.rarity].color}"><img src="${imagePath(previewCard)}" alt=""><b>${previewCard.rarity}</b></figure><figure style="--rarity:${RARITIES[previewCard.rarity].color}"><img src="${imagePath(previewCard)}" alt=""><b>${previewCard.rarity}</b></figure></div>`
      : `<div class="sum-ready-preview">${[1, 9, 4, 6, 3, 7, 8, 2, 5].map((value, index) => `<i style="--index:${index}"><b>${value}</b></i>`).join('')}<span>10</span></div>`;
    elements.miniGameReadyTitle.textContent = selectedGame === 'memory' ? '같은 카드 신호를 찾아라' : '합계 10 카드백을 지워라';
    elements.miniGameReadyCopy.textContent = selectedGame === 'memory'
      ? `카드 2장을 뒤집어 같은 인물의 짝을 완성합니다. 클리어 보상 ${number.format(rules.completionReward)}P.`
      : `드래그한 사각형 안의 숫자 합이 10이면 카드백 조각이 제거됩니다. 최대 ${number.format(MINI_GAME_RULES.sumTen.maxReward)}P.`;
    elements.miniGameStatus.textContent = selectedGame === 'memory'
      ? `${rules.label} · ${rules.pairs} PAIRS · ${rules.timeLimit} SEC`
      : `${MINI_GAME_RULES.sumTen.columns}×${MINI_GAME_RULES.sumTen.rows} · ${MINI_GAME_RULES.sumTen.timeLimit} SEC`;
    elements.miniGameReadyMode.textContent = selectedMode === 'reward'
      ? `보상 모드 · 행동력 ${MINI_GAME_RULES.energyCost} · 게임별 일일 최대 ${number.format(MINI_GAME_RULES.dailyPointCapPerGame)} P`
      : '연습 모드 · 행동력 소모 없음 · 포인트 보상 없음';
    elements.miniGameReadyMode.dataset.mode = selectedMode;
  }

  function renderResult() {
    elements.miniGameEmpty.hidden = true;
    elements.memoryBoard.hidden = true;
    elements.sumTenShell.hidden = true;
    elements.miniGameResult.hidden = false;
    elements.miniGameResultTitle.textContent = result.title;
    elements.miniGameResultScore.textContent = `${number.format(result.score)} SCORE`;
    elements.miniGameResultReward.textContent = result.mode === 'practice' ? 'PRACTICE' : `+${number.format(result.reward)} P`;
  }

  function renderMemory() {
    elements.miniGameEmpty.hidden = true;
    elements.miniGameResult.hidden = true;
    elements.sumTenShell.hidden = true;
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
    elements.sumTenShell.hidden = false;
    elements.sumTenBoard.style.setProperty('--columns', session.columns);
    elements.sumTenBoard.style.setProperty('--rows', session.rows);
    elements.sumTenBoard.innerHTML = session.tiles.map((tile) => `<div class="sum-tile${tile.active ? '' : ' inactive'}" data-sum-index="${tile.index}" style="--tile-x:${tilePosition(tile.column, session.columns)}%;--tile-y:${tilePosition(tile.row, session.rows)}%"><span>${tile.active ? tile.value : ''}</span></div>`).join('');
    elements.miniGameSelectionSum.textContent = '0';
    elements.miniGameSelectionSum.parentElement.classList.remove('invalid');
  }

  function render() {
    renderHeader();
    renderControls();
    if (session?.game === 'memory') renderMemory();
    else if (session?.game === 'sumTen') renderSumTen();
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
    else daily.bestSumTen = Math.max(daily.bestSumTen, score);
    state.points += reward;
    persist('finishMinigame');
  }

  async function finishGame({ completed = false, aborted = false } = {}) {
    if (!session) return;
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
        return showToast('미니게임 결과 저장 실패');
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
      if (!response?.ok) return showToast('미니게임 시작 실패');
      const remote = response.result;
      if (selectedGame === 'memory') {
        const cardsById = new Map(cards.map((card) => [card.id, card]));
        session = {
          id: sequence, runId: remote.runId, inputLog: [], game: 'memory', mode: selectedMode,
          difficulty: memoryDifficulty, columns: memoryDifficulty === 'advanced' ? 6 : 4,
          pairs: remote.board.length / 2,
          deck: remote.board.map((cardId) => ({ ...cardsById.get(cardId), pairId: cardId })),
          startAt: now, endAt: now + remote.timeLimit * 1000,
          open: [], matched: new Set(), matches: 0, attempts: 0, streak: 0, score: 0,
        };
      } else {
        session = {
          id: sequence, runId: remote.runId, inputLog: [], game: 'sumTen', mode: selectedMode,
          columns: 17, rows: 10,
          tiles: remote.board.map((value, index) => ({ index, value, row: Math.floor(index / 17), column: index % 17, active: true })),
          startAt: now, endAt: now + remote.timeLimit * 1000, score: 0, combinations: 0,
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

  function flipMemoryCard(index) {
    if (!session || session.game !== 'memory' || resolvingMemory || session.matched.has(index) || session.open.includes(index)) return;
    const atMs = Math.max(0, clock.now() - session.startAt);
    if (atMs > session.timeLimit * 1000) return;
    session.open.push(index);
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
    const atMs = Math.max(0, clock.now() - session.startAt);
    if (atMs > session.timeLimit * 1000) {
      sumDrag = null;
      updateSumSelection();
      return;
    }
    const evaluation = currentSumEvaluation();
    session.inputLog?.push({
      start: sumDrag.start.index,
      end: sumDrag.end.index,
      atMs,
    });
    if (evaluation?.valid) {
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

  progress();
  return { render, tick };
}
