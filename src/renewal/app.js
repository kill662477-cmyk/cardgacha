import {
  ADVENTURE_RULES, ARCHETYPES, ENHANCEMENT, GAME_RULES, PACKS, RARITIES, RARITY_ORDER,
  REWARD_RULES, STAGES, SUPPORT_ITEMS, SUPPORT_PACK,
} from './config.js';
import { computeCardPower, computeCardStats, computeFormationPower, getRaceSynergy, simulateBattle } from './battle.js';
import {
  advanceAdventureRun,
  calculateAdventureRunReward,
  claimAdventureExMilestones,
  createAdventureRun,
  getAdventureRunLimitStatus,
  normalizeAdventureRun,
  normalizeAdventureRuns,
  recordAdventureRun,
} from './adventure.js';
import {
  MATERIAL_RULES,
  applyEnhancementResult,
  consumeSelectedMaterials,
  getEnhancementGate,
  getEnhancementOdds,
  resolveEnhancement,
  selectEnhancementMaterials,
} from './enhancement.js';
import { buildCollectionModel, calculateCollectionBonuses, groupCollectionCardsByMember } from './collection.js';
import {
  addCardResults,
  addSupportResults,
  cardResultGridLayout,
  cardExpBoostSeconds,
  drawCardPack,
  drawSupportPack,
  effectivePackRates,
  useCardExpPotion,
  useSupportItem,
} from './shop.js';
import {
  applyCardExperience,
  calculateIdleReward,
  cardExpRequired,
  normalizeQuickBattle,
  recordQuickBattle,
  recoverEnergy,
  rewardRates,
} from './rewards.js';
import { assertValidGameState } from './state-schema.js';
import { createLocalGameService } from './local-game-service.js';
import { createRemoteRuntime, mergeServerSnapshot, readRemoteConfig } from './remote-runtime.js';
import { GAME_COMMAND_TYPES } from './service-contract.js';
import { createRequestCoordinator, REQUEST_PHASES } from './request-coordinator.js';
import { createMiniGameController } from './minigame-controller.js';
import { createWorldBossController } from './worldboss-controller.js';
import { createRankingController } from './ranking-controller.js';
import { createFxController } from './fx-controller.js';
import { cardVisualChrome, enhancementLabel, enhancementStarMarkup, rarityMarkMarkup } from './card-visual.js';
import { applyLocalTestProfile } from './local-test-profile.js';
import { bonusDropText, grantBonusDrop, rollAdventureBonusDrop } from './bonus-loot.js';
import { createLiveTickerController } from './live-ticker-controller.js';

const number = new Intl.NumberFormat('ko-KR');
const CARD_BACK_PATH = 'assets/card-back.jpg';
const SCREEN_IDS = new Set(['shop', 'enhance', 'collection', 'ranking', 'adventure', 'worldboss', 'minigame']);
// Temporary: world boss disabled to cap Supabase free-tier realtime/edge load until Pro (2026-07-24). Flip to true + redeploy to re-enable.
const WORLD_BOSS_ENABLED = true;
const elements = {};
let cards = [];
let cardsById = new Map();
const freshStart = new URLSearchParams(window.location.search).has('fresh');
const systemStatePreview = new URLSearchParams(window.location.search).get('ui-state');
const localGameService = createLocalGameService({ reset: freshStart });
const remoteConfig = readRemoteConfig();
const remoteRuntime = createRemoteRuntime(remoteConfig);
const remoteMode = Boolean(remoteRuntime);
const gameService = remoteMode ? {
  ...remoteRuntime.game,
  now: remoteRuntime.now,
  random: remoteRuntime.random,
  persistSnapshot: () => {},
} : localGameService;
let state = localGameService.loadSnapshot();
if (freshStart) window.history.replaceState({}, '', window.location.pathname);
let temporaryFormation = [];
let battleToken = 0;
let battleRunning = false;
let toastTimer = 0;
let rewardMode = 'offline';
let rewardPreview = null;
let activeScreen = SCREEN_IDS.has(window.location.hash.slice(1)) ? window.location.hash.slice(1) : 'adventure';
let selectedEnhanceCardId = null;
let selectedBooster = 'none';
let selectedMaterialOption = 0;
let enhanceFilter = 'all';
let enhancementResult = null;
let collectionOwnership = 'all';
let collectionRace = 'all';
let collectionRarity = 'all';
let collectionSetType = 'members';
let selectedCollectionCardId = null;
let shopTab = 'cards';
let selectedShopProduct = 'general';
let selectedShopRace = '저그';
let miniGameController = null;
let worldBossController = null;
let rankingController = null;
let liveTickerController = null;
let fxController = null;
let bridgeStatus = { canUseDonationBridge: false, soopId: null };
const requestCoordinator = createRequestCoordinator({
  clock: gameService,
  isOnline: () => navigator.onLine !== false,
  onTransition: handleRequestTransition,
});

const ARCHETYPE_DESCRIPTIONS = {
  quick: '빠른 공격 주기로 꾸준한 피해를 누적합니다. 공격속도 +28%.',
  heavy: '느리지만 강한 일격을 가합니다. 공격력 +28%, 치명타 피해 +20%p.',
  combo: '연속 타격으로 기본 피해를 증폭합니다. 연타 피해 계수 1.18배.',
  area: '여러 적이 등장하는 웨이브에 강합니다. 광역 피해 계수 1.22배.',
  boss: '보스 대상 공격이 강화됩니다. 보스 피해 계수 1.28배.',
  amplify: '치명타 신호를 증폭합니다. 치명타 확률 +9%p.',
  weaken: '공격 적중 시 적의 전투 신호를 약화합니다. 약화 효율 8%.',
  sustain: '높은 체력과 방어력으로 오래 버팁니다. 회복 효율 8%.',
};

const SYSTEM_STATES = {
  loading: {
    eyebrow: 'SYSTEM BOOT',
    title: '카드 데이터 동기화 중',
    message: '시즌2 작전 기록과 카드 정보를 불러오고 있습니다.',
    code: 'SYNC // LOCAL DATA',
    retry: false,
  },
  network: {
    eyebrow: 'CONNECTION LOST',
    title: '작전 서버 연결 실패',
    message: '네트워크 상태를 확인한 뒤 다시 연결해 주세요.',
    code: 'ERROR // DATA CHANNEL OFFLINE',
    retry: true,
    retryLabel: '다시 연결',
  },
  offline: {
    eyebrow: 'OFFLINE MODE',
    title: '네트워크 연결 없음',
    message: '연결이 복구되면 같은 요청으로 안전하게 다시 시도합니다.',
    code: 'PAUSED // NO SERVER COMMAND',
    retry: true,
    retryLabel: '연결 후 재시도',
  },
  auth: {
    eyebrow: 'SESSION EXPIRED',
    title: '로그인이 만료됨',
    message: '계정을 다시 인증한 뒤 진행 중이던 작업을 확인해 주세요.',
    code: 'AUTH // RECONNECT REQUIRED',
    retry: false,
  },
  conflict: {
    eyebrow: 'REVISION CONFLICT',
    title: '다른 기기에서 기록 변경됨',
    message: '최신 서버 기록을 불러온 뒤 현재 화면을 다시 확인해야 합니다.',
    code: 'STATE // NEWER REVISION FOUND',
    retry: true,
    retryLabel: '최신 기록 불러오기',
  },
  server: {
    eyebrow: 'COMMAND FAILED',
    title: '요청 처리 실패',
    message: '결과는 지급되지 않았습니다. 잠시 뒤 같은 요청으로 재시도해 주세요.',
    code: 'ERROR // TRANSACTION ROLLED BACK',
    retry: true,
    retryLabel: '안전하게 재시도',
  },
  // Phase 1: 점검 모드 보조 상태. runtime-config.js에서 이미 본문을 가리므로
  // 여기까지 도달하면 안 되지만, 혹시 모를 경로를 위해 정의해 둔다.
  maintenance: {
    eyebrow: 'MAINTENANCE',
    title: '시즌2 점검 중',
    message: 'SOOP 숲 로그인 복구 작업을 진행하고 있습니다. 잠시 후 다시 접속해 주세요.',
    code: 'MAINTENANCE // SOOP AUTH RESTORE',
    retry: false,
  },
};

function imagePath(card) {
  return `assets/cards/${encodeURIComponent(card.file)}`;
}

function cacheElements() {
  [
    'nickname', 'combatPower', 'energyValue', 'pointValue', 'profileCardButton', 'apiLinkButton', 'logoutButton',
    'mailButton', 'mailDialog', 'mailBadge', 'worldBossNavBadge',
    'profileCardImage', 'profileCardFallback', 'soundToggleButton', 'regionLabel',
    'stageLabel', 'stageMeter', 'battleState', 'battleClock', 'enemyName', 'enemyHpBar', 'enemyHpText',
    'enemyRow', 'partyGrid', 'synergyChip', 'resultBanner', 'stageNodes',
    'cardExpPerMinute', 'runPointReward', 'autoBattleButton',
    'formationButton', 'quickBattleButton', 'quickBattleCount', 'claimButton', 'pendingReward',
    'formationDialog', 'selectedFormation', 'inventoryGrid', 'selectionCount',
    'confirmFormation', 'clearFormation', 'toast', 'attackEcho', 'battlefield', 'offlineTime', 'offlineSummary',
    'rewardDialog', 'rewardEyebrow', 'rewardTitle', 'rewardDuration',
    'rewardCardExp', 'rewardPoints', 'rewardParty', 'rewardNote', 'confirmReward',
    'adventureScreen', 'enhanceScreen', 'enhanceOwnedCount', 'enhanceTargetList', 'enhanceCardName',
    'enhanceLockButton', 'enhanceCardPreview', 'enhanceCardMeta', 'enhanceExpText', 'enhanceExpBar',
    'cardExpPotionButton', 'cardExpPotionCount',
    'enhanceStatCompare', 'enhanceTargetLevel', 'enhanceStatus', 'enhanceSuccessRate',
    'enhanceFailRate', 'enhanceDestroyRate', 'enhanceMaterialRule', 'enhanceMaterialOptions',
    'enhanceMaterials', 'enhanceSupports', 'enhance5Count', 'enhance10Count',
    'destructionGuardCount', 'enhancePointCost', 'enhanceWarning', 'enhanceAttemptButton',
    'enhanceResult', 'enhanceConfirmDialog', 'enhanceConfirmTitle', 'enhanceConfirmSummary',
    'enhanceConfirmSuccess', 'enhanceConfirmDestroy', 'enhanceConfirmMaterials',
    'enhanceConfirmPoints', 'confirmEnhanceAttempt',
    'collectionScreen', 'collectionPanelBonus', 'collectionRing', 'collectionPercent',
    'collectionCount', 'collectionExCount', 'collectionAttackBonus', 'collectionHpBonus', 'collectionDefenseBonus',
    'collectionBossBonus', 'collectionIdleBonus', 'collectionOwnershipFilter',
    'collectionRaceFilter', 'collectionRarityFilter', 'collectionCardGrid', 'collectionSelected',
    'collectionCompletedSets', 'collectionSetTabs', 'collectionSetList',
    'dismantleButton', 'dismantleDialog', 'dismantleRaritySelect', 'dismantlePreview',
    'dismantleResult', 'dismantleConfirmWarning', 'dismantleConfirmButton', 'dismantleCancelButton',
    'cardDetailDialog', 'cardDetailTitle', 'cardDetailBody', 'cardDetailRepresentativeButton', 'cardDetailLockButton',
    'shopScreen', 'shopTabs', 'shopPointValue', 'shopBuffStatus', 'shopEyebrow',
    'shopTitle', 'shopRaceSelector', 'shopProductGrid', 'shopInventoryGrid',
    'shopDetailTitle', 'shopDetailSummary', 'shopProbabilityList', 'shopDetailNote',
    'shopResultDialog', 'shopResultTitle', 'shopResultSummary', 'shopResultGrid',
    'minigameScreen', 'worldBossScreen', 'rankingScreen',
    'systemStateLayer', 'systemStateEyebrow', 'systemStateTitle', 'systemStateMessage', 'systemStateCode', 'systemStateRetry',
    'rewardDurationBlock', 'rewardBreakdown', 'rewardEmptyState',
    'loginDialog', 'loginForm', 'loginKeyInput', 'loginSubmit', 'loginError', 'soopLoginButton',
    'orientGuide', 'orientCta', 'orientSkip',
  ].forEach((id) => { elements[id] = document.getElementById(id); });
}

function emptyStateMarkup({ stateType = 'empty', icon = 'archive-x', eyebrow, title, message, compact = false }) {
  return `<section class="ui-empty-state${compact ? ' compact' : ''}" data-state="${stateType}">
    <div class="ui-state-mark" aria-hidden="true"><img src="assets/renewal/brand/card-gacha-s2-symbol.png" alt=""><i data-lucide="${icon}"></i></div>
    <div><span>${eyebrow}</span><strong>${title}</strong><p>${message}</p></div>
  </section>`;
}

function setSystemState(type = null) {
  if (!elements.systemStateLayer) return;
  if (!type) {
    elements.systemStateLayer.hidden = true;
    elements.systemStateLayer.setAttribute('aria-hidden', 'true');
    return;
  }
  const config = SYSTEM_STATES[type] ?? SYSTEM_STATES.loading;
  elements.systemStateLayer.dataset.state = type;
  elements.systemStateLayer.hidden = false;
  elements.systemStateLayer.removeAttribute('aria-hidden');
  elements.systemStateLayer.setAttribute('aria-label', config.title);
  elements.systemStateEyebrow.textContent = config.eyebrow;
  elements.systemStateTitle.textContent = config.title;
  elements.systemStateMessage.textContent = config.message;
  elements.systemStateCode.textContent = config.code;
  elements.systemStateRetry.hidden = !config.retry;
  const retryLabel = elements.systemStateRetry.querySelector('span');
  if (retryLabel) retryLabel.textContent = config.retryLabel ?? '다시 연결';
  window.lucide?.createIcons();
}

function handleRequestTransition(requestState) {
  const button = requestState.metadata?.button;
  if (button instanceof HTMLElement) {
    if (requestState.phase === REQUEST_PHASES.PENDING) button.setAttribute('aria-busy', 'true');
    else button.removeAttribute('aria-busy');
  }
  if (requestState.phase === REQUEST_PHASES.OFFLINE) setSystemState('offline');
  else if (requestState.phase === REQUEST_PHASES.AUTH) setSystemState('auth');
  else if (requestState.phase === REQUEST_PHASES.CONFLICT) setSystemState('conflict');
  else if (requestState.phase === REQUEST_PHASES.ERROR) setSystemState('server');
  else if (requestState.phase === REQUEST_PHASES.SUCCESS && ['offline', 'server'].includes(elements.systemStateLayer?.dataset.state)) setSystemState(null);
}

function runUiOperation(operation, button, task) {
  return requestCoordinator.run(operation, task, { button });
}

function applyServerSnapshot(snapshot) {
  state = mergeServerSnapshot(snapshot, state);
  return state;
}

async function executeServerCommand(type, payload) {
  const response = await gameService.sendCommand(type, payload, state.revision);
  if (response?.ok && response.snapshot) applyServerSnapshot(response.snapshot);
  else if (response?.code === 'VERSION_CONFLICT' && response.latestSnapshot) applyServerSnapshot(response.latestSnapshot);
  return response;
}

// SOOP 숲 로그인 콜백(#soopauth= / #soopautherr=)을 fragment에서 읽는다.
// 시즌1 readAuthHash 패턴과 동일. 값을 쓰고 나면 URL에서 fragment를 제거한다.
function readSoopAuthHash() {
  const hash = window.location.hash || '';
  const params = new URLSearchParams(hash.startsWith('#') ? hash.slice(1) : hash);
  if (!params.has('soopauth') && !params.has('soopautherr')) return null;
  const code = params.get('soopauth') ?? '';
  const err = params.get('soopautherr') ?? '';
  // fragment에서 키가 서버 로그/리퍼러에 남지 않도록 즉시 제거.
  history.replaceState(null, '', window.location.pathname + window.location.search);
  return { code: code.trim(), err: err.trim() };
}

async function completeSoopAuth(exchangeCode, { onError } = {}) {
  elements.loginError.textContent = '';
  elements.loginSubmit.disabled = true;
  try {
    const signedIn = await remoteRuntime.auth.signInWithSoopExchange(exchangeCode);
    if (!signedIn?.ok) {
      const message = signedIn?.code === 'RATE_LIMITED'
        ? '로그인 시도가 많습니다. 잠시 후 다시 시도하세요.'
        : '숲 로그인에 실패했습니다. 다시 시도해 주세요.';
      if (onError) onError(message);
      else elements.loginError.textContent = message;
      return false;
    }
    const loaded = await gameService.loadSnapshot();
    if (!loaded?.ok || !loaded.snapshot) throw new Error(loaded?.code ?? 'SNAPSHOT_FAILED');
    applyServerSnapshot(loaded.snapshot);
    return true;
  } catch (error) {
    console.error(error);
    const message = '계정 연결에 실패했습니다. 다시 시도하세요.';
    if (onError) onError(message);
    else elements.loginError.textContent = message;
    return false;
  } finally {
    elements.loginSubmit.disabled = false;
  }
}

async function requireRemoteSnapshot() {
  // SOOP 숲 로그인 콜백이 fragment에 있으면 가장 먼저 처리한다.
  const soopCallback = readSoopAuthHash();
  if (soopCallback?.code) {
    const ok = await completeSoopAuth(soopCallback.code);
    if (ok) return state;
  }

  const existingToken = await remoteRuntime.auth.getAccessToken();
  if (existingToken) {
    const loaded = await gameService.loadSnapshot();
    if (loaded?.ok && loaded.snapshot) return applyServerSnapshot(loaded.snapshot);
  }
  setSystemState('auth');
  elements.loginError.textContent = '';
  if (soopCallback?.err) {
    elements.loginError.textContent = '숲 로그인에 실패했습니다. 다시 시도해 주세요.';
  }
  elements.loginDialog.showModal();
  return new Promise((resolve, reject) => {
    // SOOP 메인 버튼: 숲 인증 페이지로 리다이렉트.
    const startSoop = (event) => {
      event.preventDefault();
      const startUrl = `${remoteConfig.projectUrl}/functions/v1/soop-auth?action=start`;
      window.location.assign(startUrl);
    };
    elements.soopLoginButton?.addEventListener('click', startSoop);

    // KEY 보조 로그인.
    const submit = async (event) => {
      event.preventDefault();
      elements.loginSubmit.disabled = true;
      elements.loginError.textContent = '';
      try {
        const signedIn = await remoteRuntime.auth.signInWithLoginKey(elements.loginKeyInput.value);
        if (!signedIn?.ok) {
          elements.loginError.textContent = signedIn?.code === 'RATE_LIMITED'
            ? '로그인 시도가 많습니다. 잠시 후 다시 시도하세요.'
            : '로그인 KEY를 확인하세요.';
          return;
        }
        elements.loginKeyInput.value = '';
        const loaded = await gameService.loadSnapshot();
        if (!loaded?.ok || !loaded.snapshot) throw new Error(loaded?.code ?? 'SNAPSHOT_FAILED');
        applyServerSnapshot(loaded.snapshot);
        elements.loginDialog.close();
        elements.loginForm.removeEventListener('submit', submit);
        elements.soopLoginButton?.removeEventListener('click', startSoop);
        setSystemState(null);
        resolve(state);
      } catch (error) {
        elements.loginError.textContent = '계정 연결에 실패했습니다. 다시 시도하세요.';
        console.error(error);
      } finally {
        elements.loginSubmit.disabled = false;
      }
    };
    elements.loginForm.addEventListener('submit', submit);
    elements.loginDialog.addEventListener('cancel', (event) => event.preventDefault());
  });
}

// ===== 모바일 가로 모드 가이드 =====
// 브라우저 보안 정책상 requestFullscreen/orientation.lock 은 유저 제스처(탭 직후) 안에서만 동작.
// 따라서 자동 전환은 불가능하고, 로그인 후 게임 진입 시 가이드를 띄워 유저가 버튼을 누르게 한다.
// 그 제스처 안에서만 fullscreen + orientation.lock 을 시도.
// iOS Safari는 둘 다 미지원이라 안내만 표시되고 기기 회전에 맡김.
function isMobileDevice() {
  const ua = navigator.userAgent || '';
  const touchPoints = navigator.maxTouchPoints || 0;
  const hasTouch = touchPoints > 0 || 'ontouchstart' in window;
  const mobileUa = /Android|iPhone|iPad|iPod|Mobile|Windows Phone/i.test(ua);
  // 화면이 좁고 터치가 있으면 모바일로 간주. 태블릿도 포함.
  return hasTouch && (mobileUa || Math.min(window.innerWidth, window.innerHeight) <= 820);
}

function isPortrait() {
  // orientation.angle 이 확실하면 우선, 아니면 창 비율로 판별.
  const angle = window.screen?.orientation?.angle ?? 0;
  if (angle === 90 || angle === 270) return false;
  if (angle === 0 || angle === 180) return window.innerHeight > window.innerWidth;
  return window.innerHeight > window.innerWidth;
}

async function tryEnterFullscreenLandscape() {
  const el = document.documentElement;
  // 1) 전체화면 진입. iOS Safari는 지원 안 함.
  try {
    if (el.requestFullscreen && !document.fullscreenElement) await el.requestFullscreen();
    else if (el.webkitRequestFullscreen) el.webkitRequestFullscreen();
  } catch { /* 권한 거부 등은 무시 */ }
  // 2) 가로 방향 잠금. 전체화면 상태에서만 동작(Android Chrome). iOS 미지원.
  try {
    const lock = window.screen?.orientation?.lock;
    if (typeof lock === 'function') await lock.call(window.screen.orientation, 'landscape');
  } catch { /* 미지원/거부 무시 */ }
}

function showOrientGuideIfNeeded() {
  if (!isMobileDevice()) return;
  if (!elements.orientGuide) return;
  elements.orientGuide.hidden = false;
  window.lucide?.createIcons();
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    elements.orientGuide.hidden = true;
    elements.orientCta?.removeEventListener('click', onCta);
    elements.orientSkip?.removeEventListener('click', onSkip);
  };
  const onCta = async () => {
    // 이 탭 제스처 안에서만 fullscreen/orientation 호출이 유효.
    await tryEnterFullscreenLandscape();
    close();
  };
  const onSkip = () => close();
  elements.orientCta?.addEventListener('click', onCta);
  elements.orientSkip?.addEventListener('click', onSkip);
}

function cardWithProgress(card) {
  const progress = state.cardProgress[card.id];
  return progress ? { ...card, ...progress } : card;
}

function isPlayableCard(card) {
  return Boolean(card && card.rarity !== 'EX' && ARCHETYPES[card.archetype]);
}

function formationCards() {
  return state.formation.map((id) => cardsById.get(id)).filter((card) => isPlayableCard(card) && (state.cardCopies[card.id] ?? 0) > 0).map(cardWithProgress);
}

function ensureCardProgress() {
  cards.forEach((card) => {
    if (!state.cardProgress[card.id]) {
      state.cardProgress[card.id] = { enhancement: card.enhancement ?? 0, exp: card.exp ?? 0 };
    }
    if (state.cardCopies[card.id] === undefined) state.cardCopies[card.id] = card.copies ?? 1;
    if (state.cardLocks[card.id] === undefined) state.cardLocks[card.id] = false;
    if ((state.cardCopies[card.id] ?? 0) > 0) state.collectionRecords[card.id] = true;
  });
}

function ensureValidFormation() {
  const owned = (id) => isPlayableCard(cardsById.get(id)) && (state.cardCopies[id] ?? 0) > 0;
  const unique = [...new Set(state.formation)].filter(owned);
  if (unique.length < GAME_RULES.formationSize) {
    cards.forEach((card) => {
      if (unique.length < GAME_RULES.formationSize && owned(card.id) && !unique.includes(card.id)) unique.push(card.id);
    });
  }
  state.formation = unique.slice(0, GAME_RULES.formationSize);
}

function ensureValidRepresentativeCard() {
  const eligible = (id) => cardsById.has(id) && (state.cardCopies[id] ?? 0) > 0;
  if (eligible(state.representativeCardId)) return false;
  const fallbackId = state.formation.find(eligible) ?? cards.find((card) => eligible(card.id))?.id ?? null;
  const changed = state.representativeCardId !== fallbackId;
  state.representativeCardId = fallbackId;
  return changed;
}

function representativeCard() {
  const card = cardsById.get(state.representativeCardId);
  return card && (state.cardCopies[card.id] ?? 0) > 0 ? cardWithProgress(card) : null;
}

function ensureValidAdventureProgress() {
  state.adventureRun = normalizeAdventureRun(state.adventureRun);
  if (!state.adventureRun.active) state.autoBattle = false;
  state.currentStage = state.adventureRun.active
    ? Math.max(1, Math.min(STAGES.length, state.adventureRun.currentStage))
    : 1;
  state.clearedStage = Math.max(0, Math.min(STAGES.length, Number(state.clearedStage) || 0));
}

function productionStageNumber() {
  return Math.max(1, Math.min(STAGES.length, state.clearedStage || 1));
}

function ownedCards() {
  return cards.filter((card) => (state.cardCopies[card.id] ?? 0) > 0);
}

function currentCollectionBonuses() {
  return calculateCollectionBonuses(cards, state.collectionRecords);
}

function currentCombatBonuses() {
  // nolevel-1: accountLevelMultiplier 제거. 도감 보너스만 사용.
  return currentCollectionBonuses();
}

function cardMarkup(card, index) {
  const archetype = ARCHETYPES[card.archetype];
  const requiredExp = cardExpRequired(card.enhancement);
  const expPercent = requiredExp === 0 ? 100 : Math.min(100, card.exp / requiredExp * 100);
  const expLabel = requiredExp === 0 ? 'MAX' : `${number.format(card.exp)}/${number.format(requiredExp)}`;
  return `
    <article class="battle-card card-visual" data-card-index="${index}" data-rarity="${card.rarity}" data-stars="${card.enhancement}" style="--rarity:${RARITIES[card.rarity].color}">
      <img class="card-photo" src="${imagePath(card)}" alt="${card.member} ${card.rarity} 카드">
      <div class="card-shade"></div>
      ${cardVisualChrome(card)}
      <div class="card-info">
        <strong>${card.member}</strong>
        <span>${archetype.label} · ${card.race}</span>
        <div class="card-hp"><i></i></div>
        <div class="card-exp" title="다음 강화 경험치 ${expLabel}"><div class="card-exp-track"><i style="width:${expPercent}%"></i></div><small>${expLabel}</small></div>
      </div>
    </article>`;
}

function renderParty() {
  const formation = formationCards();
  elements.partyGrid.innerHTML = formation.map(cardMarkup).join('');
  const synergy = getRaceSynergy(formation);
  if (synergy.count >= 3) {
    const percent = Math.round((synergy.atk - 1) * 100);
    elements.synergyChip.textContent = `${synergy.race} ${synergy.count}인 시너지 · 공격력/체력 +${percent}%`;
  } else {
    elements.synergyChip.textContent = '동일 종족 3인부터 시너지 활성화';
  }
}

function stageWindow(current) {
  const stage = STAGES[current - 1] ?? STAGES[0];
  const regionStart = stage.regionIndex * 10 + 1;
  let localStart = Math.max(1, stage.stageNumber - 2);
  if (localStart + 4 > 10) localStart = 6;
  return Array.from({ length: 5 }, (_, index) => regionStart + localStart + index - 1);
}

function formatDuration(totalSeconds) {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;
  return [hours, minutes, remainder].map((value) => String(value).padStart(2, '0')).join(':');
}

function formatCompactDuration(totalSeconds) {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return `${hours}H ${String(minutes).padStart(2, '0')}M`;
}

function currentIdleReward(now = gameService.now()) {
  return calculateIdleReward(now - state.lastRewardAt, productionStageNumber(), {
    idleBonus: currentCollectionBonuses().idle,
    cardExpBoostSeconds: cardExpBoostSeconds(state.activeBuffs, state.lastRewardAt, now),
  });
}

function synchronizeTimedState(now = gameService.now()) {
  let changed = false;
  const energy = recoverEnergy(state, now);
  if (energy.recovered > 0) {
    state.actionEnergy = energy.energy;
    state.lastEnergyAt = energy.lastEnergyAt;
    changed = true;
  }
  const quickBattle = normalizeQuickBattle(state.quickBattle, now);
  if (quickBattle.windowStartedAt !== state.quickBattle.windowStartedAt || quickBattle.count !== state.quickBattle.count) {
    state.quickBattle = quickBattle;
    changed = true;
  }
  const adventureRuns = normalizeAdventureRuns(state.adventureRuns, now);
  if (adventureRuns.windowStartedAt !== state.adventureRuns?.windowStartedAt
    || adventureRuns.count !== state.adventureRuns?.count) {
    state.adventureRuns = adventureRuns;
    changed = true;
  }
  if (changed) gameService.persistSnapshot(state);
}

function renderStage() {
  const stage = STAGES[state.currentStage - 1];
  const rates = rewardRates(productionStageNumber());
  elements.regionLabel.textContent = `지역 ${stage.regionIndex + 1} · ${stage.region}`;
  elements.stageLabel.textContent = stage.id;
  elements.stageMeter.style.width = `${stage.stageNumber * 10}%`;
  elements.battlefield.dataset.region = stage.regionCode;
  // nolevel-1: 계정 EXP 분당 표시 제거. 카드 EXP 분당만 표시.
  if (elements.expPerMinute) elements.expPerMinute.textContent = rates.cardExpPerMinute.toFixed(2);
  elements.cardExpPerMinute.textContent = rates.cardExpPerMinute.toFixed(2);
  const activeRun = normalizeAdventureRun(state.adventureRun);
  const runPoints = calculateAdventureRunReward(activeRun.clearedStages).points;
  elements.runPointReward.textContent = `${number.format(runPoints)} / ${number.format(ADVENTURE_RULES.runReward.maxPointsPerRun)} P`;
  elements.stageNodes.innerHTML = stageWindow(state.currentStage).map((globalNumber) => {
    const nodeStage = STAGES[globalNumber - 1];
    const complete = globalNumber <= state.clearedStage;
    const current = globalNumber === state.currentStage;
    return `<div class="stage-node${complete ? ' complete' : ''}${current ? ' current' : ''}">
      <i>${complete ? '✓' : nodeStage.stageNumber}</i><span>${nodeStage.id}</span>
    </div>`;
  }).join('');
  renderEnemies(stage);
}

function renderEnemies(stage) {
  const count = stage.boss ? 1 : Math.min(stage.enemyCount, 5);
  const enemyClass = stage.boss ? `boss boss-${stage.regionCode}` : stage.enemyType;
  const enemyLabels = { crawler: '신호 포식체', jammer: '전파 교란체', leech: '데이터 흡수체', crusher: '중계 파쇄체' };
  const bossLabels = {
    'signal-city': '도시 포식 코어',
    'relay-base': '침묵의 중계 거신',
    'black-studio': '검은 송출 집행자',
    'data-fortress': '데이터 요새 관리자',
    'malice-core': '거대 악플러 코어',
  };
  elements.enemyName.textContent = stage.boss
    ? `${bossLabels[stage.regionCode]} · BOSS`
    : `${enemyLabels[stage.enemyType]} 편대 · ${count}기`;
  elements.enemyRow.innerHTML = Array.from({ length: count }, () => `<div class="enemy-unit ${enemyClass}"></div>`).join('');
  elements.enemyHpBar.style.width = '100%';
  elements.enemyHpText.textContent = `${number.format(stage.enemyHp)} / ${number.format(stage.enemyHp)}`;
}

function renderHeader() {
  synchronizeTimedState();
  ensureValidRepresentativeCard();
  const formation = formationCards();
  // nolevel-1: 전투력은 도감 보너스만 반영. accountLevel 곱셈 제거.
  const combatBonuses = currentCollectionBonuses();
  const collectionBonuses = combatBonuses;
  const idleReward = currentIdleReward();
  elements.nickname.textContent = state.nickname;
  const profileCard = representativeCard();
  if (profileCard) {
    const source = imagePath(profileCard);
    if (elements.profileCardImage.getAttribute('src') !== source) elements.profileCardImage.src = source;
    elements.profileCardImage.alt = `${profileCard.member} 대표카드`;
    elements.profileCardImage.hidden = false;
    elements.profileCardFallback.hidden = true;
    elements.profileCardButton.dataset.layout = RARITIES[profileCard.rarity]?.displayOnly ? 'landscape' : 'portrait';
    elements.profileCardButton.style.setProperty('--rarity', RARITIES[profileCard.rarity]?.color ?? '#c8f52e');
    elements.profileCardButton.title = `대표카드 · ${profileCard.member} ${profileCard.rarity}`;
  } else {
    elements.profileCardImage.hidden = true;
    elements.profileCardFallback.hidden = false;
    delete elements.profileCardButton.dataset.layout;
    elements.profileCardButton.title = '대표카드 없음';
  }
  // nolevel-1: accountLevel 표시 제거. combatPower만 갱신.
  elements.combatPower.textContent = number.format(computeFormationPower(formation, combatBonuses));
  elements.energyValue.textContent = `${state.actionEnergy} / ${state.maxActionEnergy}`;
  elements.pointValue.textContent = `${number.format(state.points)} P`;
  const soundEnabled = state.soundEnabled !== false;
  elements.soundToggleButton.classList.toggle('active', soundEnabled);
  elements.soundToggleButton.setAttribute('aria-pressed', String(soundEnabled));
  elements.soundToggleButton.setAttribute('aria-label', soundEnabled ? '효과음 끄기' : '효과음 켜기');
  elements.soundToggleButton.title = soundEnabled ? '효과음 끄기' : '효과음 켜기';
  if (elements.soundToggleButton.dataset.soundEnabled !== String(soundEnabled)) {
    elements.soundToggleButton.dataset.soundEnabled = String(soundEnabled);
    elements.soundToggleButton.innerHTML = `<i data-lucide="${soundEnabled ? 'volume-2' : 'volume-x'}"></i>`;
  }
  elements.pendingReward.textContent = `${formatCompactDuration(idleReward.elapsedSeconds)} · ${number.format(state.pendingPoints)}P`;
  elements.quickBattleCount.textContent = `${state.quickBattle.count}/${REWARD_RULES.quickBattleDailyLimit}`;
  const adventureStatus = getAdventureRunLimitStatus(state.adventureRuns, gameService.now());
  const activeRun = normalizeAdventureRun(state.adventureRun);
  // 자동전투 진행 중 빠른전투를 누르면 진행 중이던 스테이지 전투가 무효 처리되던 버그(battleToken 무효화) 방지.
  elements.quickBattleButton.disabled = state.autoBattle && activeRun.active;
  elements.quickBattleButton.title = elements.quickBattleButton.disabled ? '모험 진행 중에는 사용할 수 없음' : '';
  elements.autoBattleButton.classList.toggle('active', state.autoBattle);
  elements.autoBattleButton.disabled = !activeRun.active && adventureStatus.remaining <= 0;
  elements.autoBattleButton.querySelector('span').textContent = activeRun.active
    ? `${state.autoBattle ? '진행 중' : '계속하기'} · ${activeRun.clearedStages}단계`
    : `모험 시작 · ${adventureStatus.remaining}/${ADVENTURE_RULES.maxRunsPerWindow}`;
  elements.collectionPanelBonus.textContent = `+${(collectionBonuses.combatTotal * 100).toFixed(2)}%`;
}

function renderRewardReadout(now = gameService.now()) {
  const reward = currentIdleReward(now);
  elements.offlineTime.textContent = formatDuration(reward.elapsedSeconds);
  // nolevel-1: accountExp 제거. 카드 EXP만 표시.
  elements.offlineSummary.textContent = `카드 EXP +${number.format(reward.cardExp)}`;
  elements.pendingReward.textContent = `${formatCompactDuration(reward.elapsedSeconds)} · ${number.format(state.pendingPoints)}P`;
}

function renderAll() {
  renderHeader();
  renderStage();
  renderParty();
  renderRewardReadout();
  window.lucide?.createIcons();
}

function showToast(message) {
  clearTimeout(toastTimer);
  elements.toast.textContent = message;
  elements.toast.classList.add('show');
  toastTimer = setTimeout(() => elements.toast.classList.remove('show'), 2100);
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, ms)));
}

function flashAttack(event, result) {
  const card = formationCards()[event.cardIndex];
  const cardElement = elements.partyGrid.querySelector(`[data-card-index="${event.cardIndex}"]`);
  cardElement?.classList.add('attacking');
  setTimeout(() => cardElement?.classList.remove('attacking'), 190);

  elements.attackEcho.style.backgroundImage = `url("${imagePath(card)}")`;
  elements.attackEcho.style.borderColor = RARITIES[card.rarity].color;
  elements.attackEcho.dataset.cardName = card.member;
  elements.attackEcho.classList.remove('fire');
  void elements.attackEcho.offsetWidth;
  elements.attackEcho.classList.add('fire');

  const enemyUnits = elements.enemyRow.querySelectorAll('.enemy-unit');
  const target = enemyUnits[event.cardIndex % Math.max(1, enemyUnits.length)];
  const battlefieldBounds = elements.battlefield.getBoundingClientRect();
  const targetBounds = target?.getBoundingClientRect();
  const activeDamageNumbers = [...elements.battlefield.querySelectorAll('.damage-number')];
  while (activeDamageNumbers.length >= 3) activeDamageNumbers.shift().remove();

  const damage = document.createElement('span');
  damage.className = `damage-number${event.critical ? ' critical' : ''}`;
  damage.textContent = event.critical ? `CRIT ${number.format(event.damage)}` : number.format(event.damage);
  if (targetBounds) {
    damage.style.left = `${targetBounds.left - battlefieldBounds.left + targetBounds.width / 2}px`;
    damage.style.top = `${Math.max(92, targetBounds.top - battlefieldBounds.top + targetBounds.height * 0.12)}px`;
  }
  elements.battlefield.append(damage);
  damage.addEventListener('animationend', () => damage.remove(), { once: true });

  target?.classList.add('hit');
  setTimeout(() => target?.classList.remove('hit'), 180);
  const hpPercent = Math.max(0, event.enemyHp / result.enemyMaxHp * 100);
  elements.enemyHpBar.style.width = `${hpPercent}%`;
  elements.enemyHpText.textContent = `${number.format(event.enemyHp)} / ${number.format(result.enemyMaxHp)}`;
}

function flashEnemyAttack(event, result) {
  const hpPercent = Math.max(0, event.partyHp / result.partyMaxHp * 100);
  elements.partyGrid.querySelectorAll('.card-hp i').forEach((bar) => { bar.style.width = `${hpPercent}%`; });
  elements.partyGrid.animate([
    { filter: 'brightness(1)' },
    { filter: 'brightness(1.5) sepia(1) saturate(4) hue-rotate(315deg)' },
    { filter: 'brightness(1)' },
  ], { duration: 180 });
}

function showResult(victory, clearedStages) {
  elements.resultBanner.textContent = victory
    ? `스테이지 돌파 · 이번 런 ${clearedStages}개 클리어`
    : `런 종료 · ${clearedStages}개 스테이지 클리어`;
  elements.resultBanner.classList.toggle('fail', !victory);
  elements.resultBanner.classList.remove('show');
  void elements.resultBanner.offsetWidth;
  elements.resultBanner.classList.add('show');
}

function finishAdventureRun(reason) {
  if (remoteMode) {
    const runId = state.adventureRun?.runId;
    if (!runId) return;
    state.autoBattle = false;
    return runUiOperation('finishAdventureRun', null, async () => {
      const response = await executeServerCommand(GAME_COMMAND_TYPES.FINISH_ADVENTURE_RUN, { runId });
      if (!response?.ok) return response;
      state.autoBattle = false;
      state.currentStage = 1;
      renderAll();
      const result = response.result ?? {};
      showToast(`${result.clearedStages ?? 0}단계 보상 · +${number.format(result.points ?? 0)}P · 카드 EXP +${number.format(result.cardExp ?? 0)}`);
      return response;
    });
  }
  const run = normalizeAdventureRun(state.adventureRun);
  const reward = calculateAdventureRunReward(run.clearedStages);
  const bonusDrop = rollAdventureBonusDrop(run.clearedStages, gameService.random);
  const cardExp = gameService.now() < (state.activeBuffs?.cardExpEndAt ?? 0)
    ? Math.ceil(reward.cardExp * 1.5)
    : reward.cardExp;
  // nolevel-1: accountExp 보상 제거. 포인트·카드 EXP만 지급.
  state.points += reward.points;
  state.supportItems = grantBonusDrop(state.supportItems, bonusDrop);
  state.cardProgress = applyCardExperience(state.cardProgress, formationCards(), cardExp);
  state.adventureRun = normalizeAdventureRun(null);
  state.currentStage = 1;
  state.autoBattle = false;
  gameService.claimAdventureRewards(state);
  renderAll();
  const resultLabel = reason === 'complete' ? '전체 스테이지 완료' : '작전 실패';
  elements.battleState.textContent = `${resultLabel} · ${reward.clearedStages}단계 보상 지급`;
  showToast([
    `${reward.clearedStages}단계 보상 · +${number.format(reward.points)}P · 카드 EXP +${number.format(cardExp)}`,
    bonusDropText(bonusDrop),
  ].filter(Boolean).join(' · '));
}

function grantAdventureExRewards() {
  const grant = claimAdventureExMilestones(
    state.clearedStage,
    state.exMilestoneClaims,
    state.cardCopies,
    state.collectionRecords,
  );
  state.exMilestoneClaims = grant.claims;
  state.cardCopies = grant.copies;
  state.collectionRecords = grant.records;
  if (grant.awarded.length > 0) {
    const latest = grant.awarded.at(-1);
    showToast(`최고기록 ${latest.clearedStage}단계 · EX 카드 획득`);
  }
}

async function runBattle() {
  if (activeScreen !== 'adventure' || battleRunning || !state.autoBattle) return;
  const formation = formationCards();
  if (formation.length !== GAME_RULES.formationSize) return;
  const activeRun = normalizeAdventureRun(state.adventureRun);
  if (!activeRun.active) return;
  state.currentStage = activeRun.currentStage;
  battleRunning = true;
  const token = ++battleToken;
  const stage = STAGES[state.currentStage - 1];
  const result = simulateBattle(formation, stage, currentCombatBonuses());
  elements.battleState.textContent = stage.boss ? '보스 교전 중' : '자동 전투 중';
  elements.battleClock.textContent = '00.0';
  renderEnemies(stage);
  elements.partyGrid.querySelectorAll('.card-hp i').forEach((bar) => { bar.style.width = '100%'; });

  let previousAt = 0;
  for (const event of result.events) {
    await wait((event.at - previousAt) * 1000 * GAME_RULES.playbackScale);
    if (token !== battleToken) return;
    previousAt = event.at;
    elements.battleClock.textContent = event.at.toFixed(1).padStart(4, '0');
    if (event.type === 'attack') flashAttack(event, result);
    else flashEnemyAttack(event, result);
  }

  await wait(260);
  if (token !== battleToken) return;
  battleRunning = false;

  if (result.victory) {
    state.adventureRun = advanceAdventureRun(state.adventureRun);
    state.clearedStage = Math.max(state.clearedStage, state.currentStage);
    grantAdventureExRewards();
    showResult(true, state.adventureRun.clearedStages);
    if (stage.globalNumber >= STAGES.length) {
      finishAdventureRun('complete');
      return;
    }
    state.currentStage = state.adventureRun.currentStage;
    if (!remoteMode) gameService.persistSnapshot(state);
    renderAll();
    elements.battleState.textContent = state.autoBattle ? '다음 스테이지 진입' : `작전 일시 정지 · ${state.adventureRun.clearedStages}단계`;
    if (state.autoBattle) {
      await wait(1450);
      if (token === battleToken && state.autoBattle) runBattle();
    }
  } else {
    showResult(false, state.adventureRun.clearedStages);
    finishAdventureRun('failure');
  }
}

function renderFormationDialog() {
  elements.selectedFormation.innerHTML = temporaryFormation.map((id) => {
    const card = cardWithProgress(cardsById.get(id));
    return `<div class="selected-card" data-name="${card.member}" style="--rarity:${RARITIES[card.rarity].color};background-image:url('${imagePath(card)}')"></div>`;
  }).join('');
  const combatBonuses = currentCombatBonuses();
  const formationCandidates = ownedCards().filter(isPlayableCard).map(cardWithProgress).map((card) => ({
    card,
    stats: computeCardStats(card, combatBonuses),
    power: computeCardPower(card, combatBonuses),
  })).sort((left, right) => right.power - left.power || right.stats.atk - left.stats.atk || left.card.member.localeCompare(right.card.member, 'ko'));
  elements.inventoryGrid.innerHTML = formationCandidates.map(({ card, stats, power }) => {
    const selected = temporaryFormation.includes(card.id);
    return `<button class="inventory-card${selected ? ' selected' : ''}" type="button" data-card-id="${card.id}" style="--rarity:${RARITIES[card.rarity].color}">
      <img src="${imagePath(card)}" alt="">
      <div><div class="card-list-marks">${rarityMarkMarkup(card.rarity)}${enhancementStarMarkup(card.enhancement, { inline: true })}<b>보유 ×${state.cardCopies[card.id]}</b></div><span>${card.member}</span><strong class="inventory-power">전투력 ${number.format(power)}</strong><small>${ARCHETYPES[card.archetype].label} · ${card.race}</small><small>공 ${number.format(stats.atk)} · 체 ${number.format(stats.hp)} · 방 ${number.format(stats.def)}</small><small>EXP ${number.format(card.exp)}/${number.format(cardExpRequired(card.enhancement))}</small></div>
    </button>`;
  }).join('');
  elements.selectionCount.textContent = `${temporaryFormation.length} / ${GAME_RULES.formationSize}`;
  elements.confirmFormation.disabled = temporaryFormation.length !== GAME_RULES.formationSize;
}

function openFormation() {
  battleToken += 1;
  battleRunning = false;
  temporaryFormation = [...state.formation];
  renderFormationDialog();
  elements.formationDialog.showModal();
}

function toggleFormationCard(cardId) {
  const index = temporaryFormation.indexOf(cardId);
  if (index >= 0) temporaryFormation.splice(index, 1);
  else if (temporaryFormation.length < GAME_RULES.formationSize) temporaryFormation.push(cardId);
  else showToast('출전 카드는 5장까지 선택 가능');
  renderFormationDialog();
}

function clearFormationSelection() {
  if (temporaryFormation.length === 0) return;
  temporaryFormation = [];
  renderFormationDialog();
}

async function confirmFormation() {
  return runUiOperation('updateFormation', elements.confirmFormation, async () => {
    if (temporaryFormation.length !== GAME_RULES.formationSize) return;
    battleToken += 1;
    battleRunning = false;
    if (remoteMode) {
      const response = await executeServerCommand(GAME_COMMAND_TYPES.UPDATE_FORMATION, { formation: [...temporaryFormation] });
      if (!response?.ok) return response;
    } else {
      state.formation = [...temporaryFormation];
      gameService.updateFormation(state);
    }
    elements.formationDialog.close();
    renderAll();
    showToast('새 편성 적용 완료');
    return { ok: true };
  });
}

function simulateInstantRunClears() {
  const formation = formationCards();
  if (formation.length !== GAME_RULES.formationSize) return 0;
  const bonuses = currentCombatBonuses();
  let cleared = 0;
  for (const stage of STAGES) {
    if (simulateBattle(formation, stage, bonuses).victory) cleared += 1;
    else break;
  }
  return cleared;
}

function buildRewardPreview(mode, now = gameService.now()) {
  if (mode === 'quick') {
    // 빠른 전투는 스테이지 전투 연출을 생략한 즉시 모험 런이다.
    const clearedStages = simulateInstantRunClears();
    const reward = calculateAdventureRunReward(clearedStages);
    const boosted = now < (state.activeBuffs?.cardExpEndAt ?? 0);
    return {
      mode: 'quick',
      clearedStages,
      elapsedSeconds: 0,
      // nolevel-1: accountExp 제거. 카드 EXP·포인트만.
      cardExp: boosted ? Math.ceil(reward.cardExp * 1.5) : reward.cardExp,
      points: reward.points,
      createdAt: now,
    };
  }
  const elapsedMs = now - state.lastRewardAt;
  const reward = calculateIdleReward(elapsedMs, productionStageNumber(), {
    capHours: REWARD_RULES.offlineCapHours,
    idleBonus: currentCollectionBonuses().idle,
    cardExpBoostSeconds: cardExpBoostSeconds(state.activeBuffs, state.lastRewardAt, now),
  });
  return {
    ...reward,
    mode,
    points: state.pendingPoints,
    createdAt: now,
  };
}

function renderRewardDialog() {
  const formation = formationCards();
  const quick = rewardPreview.mode === 'quick';
  const runStatus = getAdventureRunLimitStatus(state.adventureRuns, gameService.now());
  elements.rewardEyebrow.textContent = quick ? '즉시 작전 정산' : '누적 작전 결과';
  elements.rewardTitle.textContent = quick ? '빠른 전투 · 즉시 클리어' : '오프라인 보상';
  if (!quick) elements.rewardDuration.textContent = formatDuration(rewardPreview.elapsedSeconds);
  // nolevel-1: 보상 다이얼로그에서 계정 EXP 행 제거.
  if (elements.rewardAccountExp) elements.rewardAccountExp.textContent = '';
  elements.rewardCardExp.textContent = `+${number.format(rewardPreview.cardExp)} × ${formation.length}`;
  elements.rewardPoints.textContent = `+${number.format(rewardPreview.points)} P`;
  elements.rewardParty.innerHTML = formation.map((card) => `
    <figure class="reward-card card-visual" style="--rarity:${RARITIES[card.rarity].color}">
      <img class="card-photo" src="${imagePath(card)}" alt="${card.member}">
      ${cardVisualChrome(card)}
      <b class="reward-card-exp">EXP +${number.format(rewardPreview.cardExp)}</b>
    </figure>`).join('');
  elements.rewardNote.textContent = quick
    ? `현재 편성 즉시 전투 · ${rewardPreview.clearedStages}단계 클리어 · 행동력 ${REWARD_RULES.quickBattleEnergy} · 모험 ${Math.max(0, runStatus.remaining)}회 남음`
    : '편성된 카드 5장에 동일한 카드 경험치가 지급됨. 최대 누적 24시간.';
  // nolevel-1: totalReward에서 accountExp 제거.
  const totalReward = rewardPreview.cardExp + rewardPreview.points;
  const empty = totalReward <= 0;
  elements.rewardDurationBlock.hidden = empty || quick;
  elements.rewardBreakdown.hidden = empty;
  elements.rewardParty.hidden = empty;
  elements.rewardNote.hidden = empty;
  elements.rewardEmptyState.hidden = !empty;
  elements.confirmReward.disabled = totalReward <= 0;
  elements.confirmReward.textContent = quick ? `행동력 ${REWARD_RULES.quickBattleEnergy} 사용` : '보상 수령';
  window.lucide?.createIcons();
}

function openRewardDialog(mode) {
  synchronizeTimedState();
  if (mode === 'quick') {
    if (state.autoBattle && normalizeAdventureRun(state.adventureRun).active) {
      showToast('모험 진행 중에는 빠른 전투를 사용할 수 없음');
      return;
    }
    if (state.quickBattle.count >= REWARD_RULES.quickBattleDailyLimit) {
      showToast('오늘 빠른 전투 횟수를 모두 사용함');
      return;
    }
    if (state.actionEnergy < REWARD_RULES.quickBattleEnergy) {
      showToast(`행동력 ${REWARD_RULES.quickBattleEnergy} 필요`);
      return;
    }
    if (getAdventureRunLimitStatus(state.adventureRuns, gameService.now()).remaining <= 0) {
      showToast('4시간당 모험 3회를 모두 사용함');
      return;
    }
  }
  battleToken += 1;
  battleRunning = false;
  rewardMode = mode;
  rewardPreview = buildRewardPreview(mode);
  renderRewardDialog();
  elements.rewardDialog.showModal();
}

function confirmReward() {
  return runUiOperation('claimAdventureRewards', elements.confirmReward, async () => {
    if (remoteMode) {
      const type = rewardMode === 'quick'
        ? GAME_COMMAND_TYPES.CLAIM_QUICK_BATTLE
        : GAME_COMMAND_TYPES.CLAIM_ADVENTURE_REWARDS;
      const payload = rewardMode === 'quick' ? {} : { mode: 'offline' };
      const response = await executeServerCommand(type, payload);
      if (!response?.ok) return response;
      rewardPreview = response.result ?? rewardPreview;
      elements.rewardDialog.close();
      renderAll();
      showToast(rewardMode === 'quick'
        ? `빠른 전투 완료 · +${number.format(response.result?.points ?? 0)}P`
        : `누적 보상 완료 · 카드 EXP +${number.format(response.result?.cardExp ?? 0)}`);
      return response;
    }
    const now = gameService.now();
    let bonusDrop = null;
    synchronizeTimedState(now);
    if (rewardMode === 'quick') {
      const runStatus = getAdventureRunLimitStatus(state.adventureRuns, now);
      if (state.quickBattle.count >= REWARD_RULES.quickBattleDailyLimit
        || state.actionEnergy < REWARD_RULES.quickBattleEnergy
        || runStatus.remaining <= 0) {
        elements.rewardDialog.close();
        showToast('빠른 전투 조건이 변경됨');
        return;
      }
      rewardPreview = buildRewardPreview('quick', now);
      if (rewardPreview.clearedStages <= 0) {
        elements.rewardDialog.close();
        showToast('편성이 1단계도 클리어하지 못함');
        return;
      }
      state.actionEnergy -= REWARD_RULES.quickBattleEnergy;
      state.lastEnergyAt = now;
      state.quickBattle = recordQuickBattle(state.quickBattle, now);
      state.adventureRuns = recordAdventureRun(state.adventureRuns, now);
      state.points += rewardPreview.points;
      bonusDrop = rollAdventureBonusDrop(rewardPreview.clearedStages, gameService.random);
      state.supportItems = grantBonusDrop(state.supportItems, bonusDrop);
      state.clearedStage = Math.max(state.clearedStage, rewardPreview.clearedStages);
      grantAdventureExRewards();
    } else {
      rewardPreview = buildRewardPreview('offline', now);
      state.lastRewardAt = now;
      state.points += rewardPreview.points;
      state.pendingPoints = 0;
    }

    // nolevel-1: accountExp 적용 제거. 카드 EXP만 갱신.
    state.cardProgress = applyCardExperience(state.cardProgress, formationCards(), rewardPreview.cardExp);
    gameService.claimAdventureRewards(state);
    elements.rewardDialog.close();
    renderAll();
    const quickSummary = rewardMode === 'quick'
      ? [
        `빠른 전투 ${rewardPreview.clearedStages}단계 · +${number.format(rewardPreview.points)}P`,
        bonusDropText(bonusDrop),
      ].filter(Boolean).join(' · ')
      : '누적 보상 정산 완료';
    showToast(quickSummary);
    return { ok: true };
  });
}

function getMaterialSelection(card, optionIndex = selectedMaterialOption) {
  return selectEnhancementMaterials(card, cards, state.cardCopies, state.cardLocks, optionIndex);
}

function enhancementReady(card) {
  if (!card || RARITIES[card.rarity]?.displayOnly) return false;
  const options = MATERIAL_RULES[card.rarity] ?? [];
  return options.some((_, index) => {
    const materials = getMaterialSelection(card, index);
    return getEnhancementGate(card, materials, state.points, 'none', state.supportItems).ready;
  });
}

function chooseEnhancementTarget() {
  const available = ownedCards().filter((card) => !RARITIES[card.rarity]?.displayOnly);
  if (available.some((card) => card.id === selectedEnhanceCardId)) return;
  selectedEnhanceCardId = available.map(cardWithProgress).find(enhancementReady)?.id ?? available[0]?.id ?? null;
  selectedMaterialOption = 0;
}

function selectedEnhancementCard() {
  const card = cardsById.get(selectedEnhanceCardId);
  return card ? cardWithProgress(card) : null;
}

function renderEnhancementList() {
  const combatBonuses = currentCombatBonuses();
  const available = ownedCards().filter((card) => !RARITIES[card.rarity]?.displayOnly).map(cardWithProgress).map((card) => ({
    card,
    ready: enhancementReady(card),
    power: computeCardPower(card, combatBonuses),
  })).sort((left, right) => Number(right.ready) - Number(left.ready) || right.power - left.power || left.card.member.localeCompare(right.card.member, 'ko'));
  const visible = enhanceFilter === 'ready' ? available.filter((entry) => entry.ready) : available;
  elements.enhanceOwnedCount.textContent = `${available.length}종`;
  elements.enhanceTargetList.innerHTML = visible.map(({ card, ready, power }) => {
    const required = cardExpRequired(card.enhancement);
    const locked = state.cardLocks[card.id];
    return `<button class="enhance-target-card${card.id === selectedEnhanceCardId ? ' selected' : ''}${ready ? ' ready' : ''}" type="button" data-enhance-card-id="${card.id}" style="--rarity:${RARITIES[card.rarity].color}">
      <img src="${imagePath(card)}" alt="">
      <div><div class="card-list-marks">${rarityMarkMarkup(card.rarity)}${enhancementStarMarkup(card.enhancement, { inline: true })}<b>×${state.cardCopies[card.id]}</b></div><span>${card.member}${locked ? ' <i class="lock-mark">LOCK</i>' : ''}</span><small>전투력 ${number.format(power)} · EXP ${number.format(card.exp)}/${number.format(required)}</small></div>
    </button>`;
  }).join('') || emptyStateMarkup({
    stateType: 'empty',
    icon: 'layers-3',
    eyebrow: 'NO UPGRADE TARGET',
    title: '조건에 맞는 카드 없음',
    message: '필터를 전체로 바꾸거나 카드 경험치와 재료를 확인하세요.',
    compact: true,
  });
}

function renderEnhancementFocus(card) {
  if (!card) {
    elements.enhanceCardName.textContent = '카드를 선택하세요';
    elements.enhanceCardPreview.innerHTML = '';
    elements.enhanceCardMeta.textContent = '';
    elements.enhanceExpText.textContent = '0 / 0';
    elements.enhanceExpBar.style.width = '0%';
    elements.cardExpPotionCount.textContent = state.supportItems.cardExpPotion ?? 0;
    elements.cardExpPotionButton.disabled = true;
    elements.enhanceStatCompare.innerHTML = '';
    return;
  }
  const required = cardExpRequired(card.enhancement);
  const expPercent = required === 0 ? 100 : Math.min(100, card.exp / required * 100);
  const combatBonuses = currentCombatBonuses();
  const currentStats = computeCardStats(card, combatBonuses);
  const nextStats = card.enhancement < 9 ? computeCardStats({ ...card, enhancement: card.enhancement + 1 }, combatBonuses) : currentStats;
  elements.enhanceCardName.textContent = card.member;
  elements.enhanceCardPreview.innerHTML = `<article class="enhance-preview-card card-visual" data-rarity="${card.rarity}" data-stars="${card.enhancement}" style="--rarity:${RARITIES[card.rarity].color}">
    <img class="card-photo" src="${imagePath(card)}" alt="${card.member}"><div class="preview-shade"></div>${cardVisualChrome(card)}<strong>${card.member}</strong>
  </article>`;
  elements.enhanceCardMeta.textContent = `${card.race} · ${ARCHETYPES[card.archetype].label} · 보유 ${state.cardCopies[card.id]}장`;
  elements.enhanceExpText.textContent = required === 0 ? 'MAX' : `${number.format(card.exp)} / ${number.format(required)}`;
  elements.enhanceExpBar.style.width = `${expPercent}%`;
  elements.cardExpPotionCount.textContent = state.supportItems.cardExpPotion ?? 0;
  elements.cardExpPotionButton.disabled = required <= 0 || card.exp >= required || (state.supportItems.cardExpPotion ?? 0) <= 0;
  elements.enhanceStatCompare.innerHTML = [
    ['공격력', currentStats.atk, nextStats.atk],
    ['체력', currentStats.hp, nextStats.hp],
    ['방어력', currentStats.def, nextStats.def],
  ].map(([label, current, next]) => `<div><dt>${label}</dt><dd>${number.format(current)} <small>→ ${number.format(next)}</small></dd></div>`).join('');
  const locked = state.cardLocks[card.id];
  elements.enhanceLockButton.innerHTML = `<i data-lucide="${locked ? 'lock-keyhole' : 'lock-open'}"></i>`;
  elements.enhanceLockButton.title = locked ? '카드 잠금 해제' : '카드 잠금';
}

function renderEnhancementConsole(card) {
  const maxed = !card || card.enhancement >= 9;
  const target = card ? Math.min(9, card.enhancement + 1) : 1;
  const options = card ? (MATERIAL_RULES[card.rarity] ?? []) : [];
  if (selectedMaterialOption >= options.length) selectedMaterialOption = 0;
  const materials = card ? getMaterialSelection(card) : { rule: null, selected: [], available: 0, ready: false };
  const odds = card && !maxed ? getEnhancementOdds(card, selectedBooster) : { success: 0, fail: 0, destroy: 0 };
  const gate = card ? getEnhancementGate(card, materials, state.points, selectedBooster, state.supportItems) : { ready: false, reason: '강화할 카드를 선택하세요.' };
  const pointCost = card && target === 9 ? ENHANCEMENT.plusNinePointCost : 0;

  elements.enhanceTargetLevel.textContent = card ? `${enhancementLabel(card.enhancement)} → ${enhancementLabel(target)}` : '0성 → 1성';
  const statusTone = gate.ready ? (odds.destroy > 0 ? 'danger' : odds.fail > 0 ? 'caution' : 'ready') : 'idle';
  elements.enhanceStatus.textContent = maxed ? 'MAX' : statusTone === 'danger' ? '파괴 위험' : statusTone === 'caution' ? '도전 가능' : statusTone === 'ready' ? '확정 성공' : '대기';
  elements.enhanceStatus.dataset.tone = statusTone;
  elements.enhanceSuccessRate.textContent = `${odds.success}%`;
  elements.enhanceFailRate.textContent = `${odds.fail}%`;
  elements.enhanceDestroyRate.textContent = `${odds.destroy}%`;
  elements.enhanceMaterialRule.textContent = materials.rule ? `${materials.rule.rarity} 중복 ${materials.rule.count}장 · 가용 ${materials.available}` : '-';
  elements.enhanceMaterialOptions.innerHTML = options.length > 1 ? options.map((rule, index) => `<button class="${index === selectedMaterialOption ? 'active' : ''}" type="button" data-material-option="${index}">${rule.rarity} ×${rule.count}</button>`).join('') : '';
  elements.enhanceMaterials.innerHTML = materials.rule ? Array.from({ length: materials.rule.count }, (_, index) => {
    const material = cardsById.get(materials.selected[index]);
    return material
      ? `<div class="enhance-material-card" style="--rarity:${RARITIES[material.rarity].color}"><img src="${imagePath(material)}" alt=""><span>${material.member} · ${material.rarity}</span></div>`
      : '<div class="enhance-material-card empty">재료 부족</div>';
  }).join('') : '<div class="enhance-material-card empty">대상 선택 필요</div>';

  elements.enhance5Count.textContent = state.supportItems.enhance5;
  elements.enhance10Count.textContent = state.supportItems.enhance10;
  elements.destructionGuardCount.textContent = state.supportItems.destructionGuard;
  elements.enhanceSupports.querySelectorAll('[data-booster]').forEach((button) => {
    const booster = button.dataset.booster;
    const unavailable = booster !== 'none' && (state.supportItems[booster] ?? 0) <= 0;
    const wrongLevel = (booster === 'enhance5' || booster === 'enhance10') ? target < 4 : booster === 'destructionGuard' && target < 7;
    button.disabled = !card || maxed || unavailable || wrongLevel;
    button.classList.toggle('active', booster === selectedBooster);
  });
  elements.enhancePointCost.textContent = `${number.format(pointCost)} P`;
  elements.enhanceWarning.textContent = !gate.ready
    ? gate.reason
    : odds.destroy > 0
      ? `파괴 ${odds.destroy}% · 실패 또는 파괴 시 재료가 소모되며, 파괴 시 강화 수치가 0으로 초기화됩니다. (본카드는 유지)`
      : odds.fail > 0
        ? `실패 ${odds.fail}% · 실패 시 재료만 소모되고 대상 카드와 경험치는 유지됩니다.`
        : `확정 성공 구간 · 재료 소모 후 ${enhancementLabel(target)}으로 강화됩니다.`;
  elements.enhanceAttemptButton.disabled = !gate.ready;
  elements.enhanceAttemptButton.querySelector('span').textContent = maxed ? '9성 강화 완료' : `${enhancementLabel(target)} 강화 시도`;
  elements.enhanceResult.className = `enhance-result${enhancementResult ? ` show ${enhancementResult.type}` : ''}`;
  elements.enhanceResult.textContent = enhancementResult?.message ?? '';
}

function renderEnhancement() {
  chooseEnhancementTarget();
  const card = selectedEnhancementCard();
  renderEnhancementList();
  renderEnhancementFocus(card);
  renderEnhancementConsole(card);
  document.querySelectorAll('[data-enhance-filter]').forEach((button) => button.classList.toggle('active', button.dataset.enhanceFilter === enhanceFilter));
  window.lucide?.createIcons();
}

function percentText(value) {
  return `+${((value ?? 0) * 100).toFixed(2)}%`;
}

function collectionRewardText(reward) {
  const labels = { attack: '공격력', hp: '체력', defense: '방어력', bossDamage: '보스 피해' };
  return `${labels[reward.stat] ?? reward.stat} ${percentText(reward.amount)}`;
}

function collectionVisibleCards() {
  return cards.filter((card) => {
    const currentlyOwned = (state.cardCopies[card.id] ?? 0) > 0;
    if (collectionOwnership === 'owned' && !currentlyOwned) return false;
    if (collectionOwnership === 'unowned' && currentlyOwned) return false;
    if (collectionRace !== 'all' && card.race !== collectionRace) return false;
    if (collectionRarity !== 'all' && card.rarity !== collectionRarity) return false;
    return true;
  });
}

function renderCollectionSummary(bonuses) {
  const percent = Math.round(bonuses.model.ratio * 100);
  elements.collectionRing.style.setProperty('--progress', `${bonuses.model.ratio * 360}deg`);
  elements.collectionPercent.textContent = `${percent}%`;
  elements.collectionCount.textContent = `전투 카드 ${bonuses.model.registered} / ${bonuses.model.total}`;
  elements.collectionExCount.textContent = `${bonuses.model.exRegistered} / ${bonuses.model.exTotal}`;
  elements.collectionAttackBonus.textContent = percentText(bonuses.attack);
  elements.collectionHpBonus.textContent = percentText(bonuses.hp);
  elements.collectionDefenseBonus.textContent = percentText(bonuses.defense);
  elements.collectionBossBonus.textContent = percentText(bonuses.bossDamage);
  elements.collectionIdleBonus.textContent = percentText(bonuses.idle);
}

function renderCollectionGrid() {
  const visible = collectionVisibleCards();
  if (!visible.some((card) => card.id === selectedCollectionCardId)) selectedCollectionCardId = visible[0]?.id ?? cards[0]?.id ?? null;
  const allByMember = new Map();
  cards.forEach((card) => {
    if (!allByMember.has(card.member)) allByMember.set(card.member, []);
    allByMember.get(card.member).push(card);
  });
  elements.collectionCardGrid.innerHTML = groupCollectionCardsByMember(visible).map(({ member, cards: memberCards }) => {
    const allMemberCards = allByMember.get(member) ?? memberCards;
    const owned = allMemberCards.filter((card) => Boolean(state.collectionRecords[card.id])).length;
    const displayOnlyGroup = allMemberCards.every((card) => RARITIES[card.rarity]?.displayOnly);
    const cardMarkup = memberCards.map((card) => {
      const registered = Boolean(state.collectionRecords[card.id]);
      const copies = state.cardCopies[card.id] ?? 0;
      const art = registered ? imagePath(card) : CARD_BACK_PATH;
      return `<button class="collection-card card-visual${registered ? '' : ' unregistered'}${card.id === selectedCollectionCardId ? ' selected' : ''}${card.id === state.representativeCardId ? ' representative' : ''}" type="button" data-collection-card-id="${card.id}" data-rarity="${card.rarity}" data-stars="${card.enhancement}" style="--rarity:${RARITIES[card.rarity].color}">
        <img class="card-photo" src="${art}" alt="${registered ? card.member : '미등록 카드 뒷면'}"><div class="collection-card-shade"></div>${cardVisualChrome(card, { showEnhancement: registered })}<strong>${registered ? card.member : '???'}</strong><small>${registered ? `${card.race} · 보유 ${copies}` : '획득 기록 없음'}</small>
      </button>`;
    }).join('');
    return `<section class="collection-member-group${displayOnlyGroup ? ' ex-archive' : ''}" data-collection-member="${member}">
      <header class="collection-member-header"><h3>${displayOnlyGroup ? 'EX 전시 아카이브' : member}</h3><span>${owned}/${allMemberCards.length}${displayOnlyGroup ? ' · 전투 미참여' : ''}</span></header>
      <div class="collection-member-cards">${cardMarkup}</div>
    </section>`;
  }).join('') || emptyStateMarkup({
    stateType: 'empty',
    icon: 'scan-search',
    eyebrow: 'ARCHIVE EMPTY',
    title: '조건에 맞는 카드 없음',
    message: '보유 상태, 종족 또는 등급 필터를 변경하세요.',
  });
}

function renderCollectionSelected(bonuses) {
  const base = cardsById.get(selectedCollectionCardId);
  if (!base) {
    elements.collectionSelected.innerHTML = '<p class="collection-empty">카드를 선택하세요.</p>';
    return;
  }
  const card = cardWithProgress(base);
  const registered = Boolean(state.collectionRecords[card.id]);
  const copies = state.cardCopies[card.id] ?? 0;
  const stats = computeCardStats(card, bonuses);
  const power = computeCardPower(card, bonuses);
  const art = registered ? imagePath(card) : CARD_BACK_PATH;
  elements.collectionSelected.innerHTML = `
    <div class="collection-selected-card card-visual${registered ? '' : ' unregistered'}" data-rarity="${card.rarity}" style="--rarity:${RARITIES[card.rarity].color}"><img class="card-photo" src="${art}" alt="${registered ? card.member : '미등록 카드 뒷면'}">${cardVisualChrome(card, { showEnhancement: registered })}</div>
    <div class="collection-selected-copy" style="--rarity:${RARITIES[card.rarity].color}">
      <div class="card-copy-marks">${rarityMarkMarkup(card.rarity)}${registered ? enhancementStarMarkup(card.enhancement, { inline: true }) : ''}</div><h2>${registered ? card.member : '미등록 카드'}</h2><span>${card.race} · ${ARCHETYPES[card.archetype]?.label ?? '전시 전용'}</span>
      ${stats ? `<dl><div class="power"><dt>전투력</dt><dd>${number.format(power)}</dd></div><div><dt>공격력</dt><dd>${number.format(stats.atk)}</dd></div><div><dt>체력</dt><dd>${number.format(stats.hp)}</dd></div><div><dt>방어력</dt><dd>${number.format(stats.def)}</dd></div></dl>` : '<dl><div><dt>용도</dt><dd>도감 전시 전용</dd></div></dl>'}
      <div class="registered${registered ? '' : ' missing'}">${registered ? `등록 완료 · 현재 ${copies}장 보유${card.id === state.representativeCardId ? ' · 대표카드' : ''}` : '최초 획득 시 영구 등록'}</div>
    </div>`;
}

function renderCardDetail(cardId) {
  const base = cardsById.get(cardId);
  if (!base) return false;
  const card = cardWithProgress(base);
  const rarity = RARITIES[card.rarity];
  const copies = state.cardCopies[card.id] ?? 0;
  const registered = Boolean(state.collectionRecords[card.id]);
  const locked = Boolean(state.cardLocks[card.id]);
  const representative = state.representativeCardId === card.id;
  const archetype = ARCHETYPES[card.archetype];
  const stats = computeCardStats(card, currentCombatBonuses());
  const requiredExp = cardExpRequired(card.enhancement);
  const expPercent = requiredExp === 0 ? 100 : Math.min(100, card.exp / requiredExp * 100);
  const expText = requiredExp === 0 ? 'MAX' : `${number.format(card.exp)} / ${number.format(requiredExp)}`;
  const status = registered
    ? `도감 등록 · ${copies > 0 ? `보유 ${copies}장` : '현재 미보유'}`
    : '미등록 카드';
  const detailArt = registered ? imagePath(card) : CARD_BACK_PATH;
  const statsMarkup = stats ? `
    <dl class="card-detail-stats">
      <div><dt>공격력</dt><dd>${number.format(stats.atk)}</dd></div>
      <div><dt>체력</dt><dd>${number.format(stats.hp)}</dd></div>
      <div><dt>방어력</dt><dd>${number.format(stats.def)}</dd></div>
      <div><dt>공격속도</dt><dd>${stats.speed.toFixed(2)}</dd></div>
      <div><dt>치명타</dt><dd>${(stats.crit * 100).toFixed(1)}%</dd></div>
      <div><dt>치명타 피해</dt><dd>${(stats.critDamage * 100).toFixed(0)}%</dd></div>
    </dl>
    <section class="card-detail-passive"><span>COMBAT PASSIVE</span><strong>${archetype.label}</strong><p>${ARCHETYPE_DESCRIPTIONS[card.archetype]}</p></section>
    <div class="card-detail-exp"><div><span>다음 강화 경험치</span><b>${expText}</b></div><div class="card-detail-exp-track"><i style="width:${expPercent}%"></i></div></div>`
    : '<p class="card-detail-display-only">EX 등급은 도감 전시 전용입니다. 모험, 월드보스와 전투력 계산에는 참여하지 않습니다.</p>';

  elements.cardDetailDialog.dataset.cardId = card.id;
  elements.cardDetailDialog.style.setProperty('--rarity', rarity?.color ?? '#f7f7f2');
  elements.cardDetailTitle.textContent = registered ? card.member : '미등록 카드';
  elements.cardDetailBody.innerHTML = `
    <div class="card-detail-visual-shell">
      <article class="card-detail-card card-visual${registered ? '' : ' unregistered'}" data-card-detail-tilt data-rarity="${card.rarity}" data-stars="${card.enhancement}" style="--rarity:${rarity?.color ?? '#f7f7f2'}">
        <img class="card-photo" src="${detailArt}" alt="${registered ? card.member : '미등록 카드 뒷면'}"><div class="shade"></div>${cardVisualChrome(card, { showEnhancement: registered })}<strong>${registered ? card.member : '???'}</strong>
      </article>
    </div>
    <section class="card-detail-copy">
      <div class="card-detail-status${registered ? '' : ' missing'}">${status}${representative ? ' · 대표카드' : ''}${locked ? ' · LOCKED' : ''}</div>
      <h3>${registered ? card.member : '미등록 카드'}</h3>
      <div class="card-detail-id">CARD ID · ${card.id}</div>
      <div class="card-detail-tags"><span>${card.race}</span><span>${archetype?.label ?? '전시 전용'}</span><span>${card.rarity} 등급</span></div>
      ${statsMarkup}
    </section>`;
  elements.cardDetailRepresentativeButton.disabled = copies <= 0 || representative;
  elements.cardDetailRepresentativeButton.classList.toggle('active', representative);
  elements.cardDetailRepresentativeButton.innerHTML = `<i data-lucide="star"></i><span>${representative ? '대표카드 설정됨' : '대표카드 설정'}</span>`;
  elements.cardDetailLockButton.disabled = copies <= 0;
  elements.cardDetailLockButton.classList.toggle('active', locked);
  elements.cardDetailLockButton.innerHTML = `<i data-lucide="${locked ? 'lock-keyhole' : 'lock-open'}"></i><span>${locked ? '잠금 해제' : '카드 잠금'}</span>`;
  window.lucide?.createIcons();
  return true;
}

function openCardDetail(cardId) {
  if (!renderCardDetail(cardId)) return;
  if (!elements.cardDetailDialog.open) elements.cardDetailDialog.showModal();
}

async function toggleCardDetailLock() {
  const cardId = elements.cardDetailDialog.dataset.cardId;
  if (!cardId || (state.cardCopies[cardId] ?? 0) <= 0) return;
  if (remoteMode) {
    return runUiOperation('setCardLock', elements.cardDetailLockButton, async () => {
      const response = await executeServerCommand(GAME_COMMAND_TYPES.SET_CARD_LOCK, { cardId, locked: !state.cardLocks[cardId] });
      if (!response?.ok) return response;
      renderCardDetail(cardId);
      renderCollection();
      renderEnhancement();
      return response;
    });
  }
  state.cardLocks[cardId] = !state.cardLocks[cardId];
  gameService.persistSnapshot(state);
  renderCardDetail(cardId);
  renderCollection();
  renderEnhancement();
  showToast(state.cardLocks[cardId] ? '카드 잠금 완료' : '카드 잠금 해제');
}

async function setRepresentativeCardFromDetail() {
  const cardId = elements.cardDetailDialog.dataset.cardId;
  const card = cardsById.get(cardId);
  if (!card || (state.cardCopies[cardId] ?? 0) <= 0) return;
  if (state.representativeCardId === cardId) {
    showToast('현재 대표카드입니다');
    return;
  }
  if (remoteMode) {
    return runUiOperation('setRepresentativeCard', elements.cardDetailRepresentativeButton, async () => {
      const response = await executeServerCommand(GAME_COMMAND_TYPES.SET_REPRESENTATIVE_CARD, { cardId });
      if (!response?.ok) return response;
      renderHeader();
      renderCollection();
      renderCardDetail(cardId);
      showToast(`${card.member} 대표카드 설정 완료`);
      return response;
    });
  }
  state.representativeCardId = cardId;
  gameService.persistSnapshot(state);
  renderHeader();
  renderCollection();
  renderCardDetail(cardId);
  showToast(`${card.member} 대표카드 설정 완료`);
}

function openRepresentativeCardDetail() {
  const card = representativeCard();
  if (!card) return;
  selectedCollectionCardId = card.id;
  showScreen('collection');
  renderCollection();
  openCardDetail(card.id);
}

function updateCardDetailTilt(event) {
  if (event.pointerType === 'touch') return;
  const card = event.target.closest('[data-card-detail-tilt]');
  if (!card) return;
  const rect = card.getBoundingClientRect();
  const x = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
  const y = Math.max(0, Math.min(1, (event.clientY - rect.top) / rect.height));
  card.style.setProperty('--rx', `${((.5 - y) * 8).toFixed(2)}deg`);
  card.style.setProperty('--ry', `${((x - .5) * 8).toFixed(2)}deg`);
  card.style.setProperty('--shine-x', `${(x * 100).toFixed(1)}%`);
  card.style.setProperty('--shine-y', `${(y * 100).toFixed(1)}%`);
}

function resetCardDetailTilt(event) {
  const card = event.target.closest?.('[data-card-detail-tilt]');
  if (!card || card.contains(event.relatedTarget)) return;
  card.style.setProperty('--rx', '0deg');
  card.style.setProperty('--ry', '0deg');
  card.style.setProperty('--shine-x', '50%');
  card.style.setProperty('--shine-y', '35%');
}

function renderCollectionSets(model) {
  const allGroups = Object.values(model.groups).flat();
  elements.collectionCompletedSets.textContent = `${allGroups.filter((group) => group.complete).length} 완료`;
  const groups = model.groups[collectionSetType] ?? [];
  elements.collectionSetList.innerHTML = groups.map((group) => {
    const progress = group.type === 'overall'
      ? Math.min(1, model.ratio / Number(group.key))
      : group.registered / Math.max(1, group.total);
    const progressLabel = group.type === 'overall'
      ? `${model.registered}/${Math.ceil(model.total * Number(group.key))}`
      : `${group.registered}/${group.total}`;
    return `<article class="collection-set-row${group.complete ? ' complete' : ''}"><div><strong>${group.label}</strong><span>${progressLabel}</span></div><small>${collectionRewardText(group.reward)}${group.complete ? ' · 적용 중' : ''}</small><div class="collection-set-progress"><i style="width:${Math.min(100, progress * 100)}%"></i></div></article>`;
  }).join('') || '<p class="collection-empty">해당 컬렉션 없음</p>';
  elements.collectionSetTabs.querySelectorAll('[data-collection-set]').forEach((button) => button.classList.toggle('active', button.dataset.collectionSet === collectionSetType));
}

function renderCollectionFilters() {
  const rarities = [...RARITY_ORDER, ...(cards.some((card) => card.rarity === 'EX') ? ['EX'] : [])];
  elements.collectionRarityFilter.innerHTML = `<button class="${collectionRarity === 'all' ? 'active' : ''}" type="button" data-collection-rarity="all">전체</button>${rarities.map((rarity) => `<button class="${collectionRarity === rarity ? 'active' : ''}" type="button" data-collection-rarity="${rarity}">${rarity}</button>`).join('')}`;
  elements.collectionOwnershipFilter.querySelectorAll('[data-collection-owned]').forEach((button) => button.classList.toggle('active', button.dataset.collectionOwned === collectionOwnership));
  elements.collectionRaceFilter.querySelectorAll('[data-collection-race]').forEach((button) => button.classList.toggle('active', button.dataset.collectionRace === collectionRace));
}

function renderCollection() {
  const bonuses = currentCollectionBonuses();
  renderCollectionSummary(bonuses);
  renderCollectionFilters();
  renderCollectionGrid();
  // nolevel-1: levelMultiplier 제거. 도감 보너스만 전달.
  renderCollectionSelected(bonuses);
  renderCollectionSets(bonuses.model);
  window.lucide?.createIcons();
}

const PACK_IMAGES = {
  general: 'assets/renewal/packs/pack-general.webp',
  elite: 'assets/renewal/packs/pack-elite.webp',
  premium: 'assets/renewal/packs/pack-premium.webp',
  저그: 'assets/renewal/packs/pack-zerg.webp',
  테란: 'assets/renewal/packs/pack-terran.webp',
  프로토스: 'assets/renewal/packs/pack-protoss.webp',
};

const SHOP_CARD_PRODUCTS = {
  general: { packKey: 'general', eyebrow: 'STANDARD SUPPLY', accent: '#c8f52e' },
  elite: { packKey: 'elite', eyebrow: 'ELITE SUPPLY', accent: '#62d4d0' },
  premium: { packKey: 'premium', eyebrow: 'PREMIUM SUPPLY', accent: '#e5bd4e' },
  zerg: { packKey: 'race', race: '저그', eyebrow: 'ZERG ARCHIVE', accent: '#d95488' },
  terran: { packKey: 'race', race: '테란', eyebrow: 'TERRAN ARCHIVE', accent: '#77c8c2' },
  protoss: { packKey: 'race', race: '프로토스', eyebrow: 'PROTOSS ARCHIVE', accent: '#e5bd4e' },
};

const SHOP_CARD_PRODUCT_ORDER = ['general', 'elite', 'premium', 'zerg', 'terran', 'protoss'];

const ITEM_ICONS = {
  행동력: 'battery-charging', 강화: 'chevrons-up', 경험치: 'radio', 교환권: 'ticket', 초기화: 'rotate-ccw',
};

const ITEM_IMAGES = {
  energySmall: 'assets/renewal/shop/battery.webp',
  energyMedium: 'assets/renewal/shop/battery.webp',
  energyLarge: 'assets/renewal/shop/battery.webp',
  enhance5: 'assets/renewal/shop/enhance-catalyst.webp',
  enhance10: 'assets/renewal/shop/enhance-catalyst.webp',
  destructionGuard: 'assets/renewal/shop/destruction-guard.webp',
  exp30m: 'assets/renewal/shop/exp-amplifier.webp',
  exp2h: 'assets/renewal/shop/exp-amplifier.webp',
  cardExpPotion: 'assets/renewal/shop/exp-amplifier.webp',
  generalTicket: 'assets/renewal/shop/pack-ticket.webp',
  eliteTicket: 'assets/renewal/shop/pack-ticket.webp',
  raceTicket: 'assets/renewal/shop/pack-ticket.webp',
  premiumTicket: 'assets/renewal/shop/pack-ticket.webp',
};

function shopPackImage(packKey, race = selectedShopRace) {
  return packKey === 'race' ? PACK_IMAGES[race] : PACK_IMAGES[packKey];
}

function renderShopBuff(now = gameService.now()) {
  const remaining = Math.max(0, (state.activeBuffs?.cardExpEndAt ?? 0) - now);
  elements.shopBuffStatus.classList.toggle('active', remaining > 0);
  elements.shopBuffStatus.innerHTML = remaining > 0
    ? `<b>카드 EXP +50%</b><br>${formatDuration(Math.ceil(remaining / 1000))} 남음`
    : '활성 작전 버프 없음';
}

function cardPackProductMarkup(productId) {
  const product = SHOP_CARD_PRODUCTS[productId];
  const pack = PACKS[product.packKey];
  const packName = product.race ? `${product.race} ${pack.name}` : pack.name;
  const selected = selectedShopProduct === productId;
  const raceAttribute = product.race ? ` data-buy-race="${product.race}"` : '';
  return `<article class="shop-product${selected ? ' selected' : ''}" data-shop-product="${productId}" style="--accent:${product.accent}">
    <div class="shop-product-visual"><img src="${shopPackImage(product.packKey, product.race)}" alt="${packName}"></div>
    <div class="shop-product-copy"><span>${product.eyebrow}</span><h3>${packName}</h3><p><b>${number.format(pack.price)}P</b><i>${pack.count}장 · 확정 등급 없음</i></p></div>
    <div class="shop-buy-row"><button type="button" data-buy-card-pack="${product.packKey}"${raceAttribute} data-buy-count="1" ${state.points < pack.price ? 'disabled' : ''}><b>1개 구매</b><small>${number.format(pack.price)}P · ${pack.count}장</small></button><button type="button" data-buy-card-pack="${product.packKey}"${raceAttribute} data-buy-count="10" ${state.points < pack.price * 10 ? 'disabled' : ''}><b>10개 구매</b><small>${number.format(pack.price * 10)}P · ${pack.count * 10}장</small></button></div>
  </article>`;
}

function supportPackProductMarkup() {
  return `<article class="shop-product support selected" data-shop-product="support" style="--accent:#62d4d0">
    <div class="shop-product-visual"><img src="assets/renewal/shop/support-case.webp" alt="${SUPPORT_PACK.name}"></div>
    <div class="shop-product-copy"><span>TACTICAL ITEM</span><h3>${SUPPORT_PACK.name}</h3><p>행동력·강화·경험치·초기화권·카드팩 교환권</p></div>
    <div class="shop-buy-row"><button type="button" data-buy-support="1" ${state.points < SUPPORT_PACK.price ? 'disabled' : ''}><b>1회 보급</b><small>${number.format(SUPPORT_PACK.price)}P</small></button><button type="button" data-buy-support="10" ${state.points < SUPPORT_PACK.tenPrice ? 'disabled' : ''}><b>10회 보급</b><small>${number.format(SUPPORT_PACK.tenPrice)}P · 희귀 1개 보장</small></button></div>
  </article>`;
}

function shopItemMarkup(itemId) {
  const item = SUPPORT_ITEMS[itemId];
  const count = state.supportItems[itemId] ?? 0;
  const directlyUsable = Boolean(item.energy || item.durationMinutes || item.pack || item.cardExp || item.reset);
  return `<article class="shop-item-row">
    <div class="shop-item-icon">${ITEM_IMAGES[itemId] ? `<img src="${ITEM_IMAGES[itemId]}" alt="">` : `<i data-lucide="${ITEM_ICONS[item.category] ?? 'box'}"></i>`}</div>
    <div class="shop-item-copy"><b>${item.name}</b><span>${item.effect}</span><small>보유 ${count}개</small></div>
    <button class="shop-item-action" type="button" data-use-shop-item="${itemId}" ${count <= 0 || !directlyUsable ? 'disabled' : ''}>${item.pack ? '교환' : item.cardExp ? '강화' : '사용'}</button>
  </article>`;
}

function renderShopDetail() {
  if (shopTab === 'cards') {
    const product = SHOP_CARD_PRODUCTS[selectedShopProduct] ?? SHOP_CARD_PRODUCTS.general;
    const pack = PACKS[product.packKey];
    const rates = effectivePackRates(product.packKey, cards, product.race ?? null);
    elements.shopDetailTitle.textContent = product.race ? `${product.race} ${pack.name}` : pack.name;
    elements.shopDetailSummary.innerHTML = `<strong>${number.format(pack.price)} P</strong><span>팩 1개 · 카드 ${pack.count}장</span>`;
    elements.shopProbabilityList.innerHTML = RARITY_ORDER.map((rarity) => `<div class="shop-rate-row" style="--rate-color:${RARITIES[rarity].color}"><b>${rarity}</b><span>${(rates[rarity] ?? 0).toFixed(rates[rarity] >= 1 ? 2 : 4)}%</span></div>`).join('');
    elements.shopDetailNote.textContent = product.race
      ? `${product.race} 카드만 등장. 인물군을 좁히는 대신 상위 등급 확률이 더 낮음.`
      : '등급 확정 슬롯과 누적 천장 없음. 표시 확률로 모든 카드 슬롯을 독립 추첨.';
  } else if (shopTab === 'support') {
    elements.shopDetailTitle.textContent = SUPPORT_PACK.name;
    elements.shopDetailSummary.innerHTML = `<strong>${number.format(SUPPORT_PACK.price)} P</strong><span>1회 1개 · 10회 희귀 보급품 최소 1개</span>`;
    elements.shopProbabilityList.innerHTML = Object.entries(SUPPORT_PACK.items).map(([itemId, rate]) => {
      const item = SUPPORT_ITEMS[itemId];
      return `<div class="shop-rate-row"><b>${item.name}</b><span>${rate}%</span><small>${item.effect}</small></div>`;
    }).join('');
    elements.shopDetailNote.textContent = '10회 결과의 앞 9개에 희귀 보급품이 없을 때만 10번째 보장 전용 확률표 적용.';
  } else {
    elements.shopDetailTitle.textContent = '아이템 사용 규칙';
    elements.shopDetailSummary.innerHTML = `<strong>${Object.values(state.supportItems).reduce((sum, count) => sum + count, 0)}개</strong><span>현재 보유 보급품</span>`;
    elements.shopProbabilityList.innerHTML = [
      ['행동력', '기본 최대치의 2배까지 초과 충전'],
      ['경험치', '+50% 고정 · 같은 효과는 시간만 연장'],
      ['강화', '강화 화면에서 시도 단계에 맞춰 사용'],
      ['초기화', '사용한 모험 시작 또는 빠른 전투 횟수를 최대치로 복구'],
      ['교환권', '동일 카드팩의 장수와 확률 그대로 적용'],
    ].map(([name, rule]) => `<div class="shop-rate-row"><b>${name}</b><span></span><small>${rule}</small></div>`).join('');
    elements.shopDetailNote.textContent = '모든 아이템은 만료 기간 없음.';
  }
}

function renderShop() {
  if (shopTab === 'cards' && !SHOP_CARD_PRODUCTS[selectedShopProduct]) selectedShopProduct = 'general';
  elements.shopPointValue.textContent = `${number.format(state.points)} P`;
  elements.shopTabs.querySelectorAll('[data-shop-tab]').forEach((button) => button.classList.toggle('active', button.dataset.shopTab === shopTab));
  elements.shopProductGrid.hidden = shopTab === 'inventory';
  elements.shopInventoryGrid.hidden = shopTab !== 'inventory';
  elements.shopRaceSelector.hidden = shopTab !== 'inventory';
  elements.shopRaceSelector.querySelectorAll('[data-shop-race]').forEach((button) => button.classList.toggle('active', button.dataset.shopRace === selectedShopRace));
  if (shopTab === 'cards') {
    elements.shopEyebrow.textContent = 'CARD SUPPLY';
    elements.shopTitle.textContent = '카드팩';
    elements.shopProductGrid.innerHTML = SHOP_CARD_PRODUCT_ORDER.map(cardPackProductMarkup).join('');
  } else if (shopTab === 'support') {
    selectedShopProduct = 'support';
    elements.shopEyebrow.textContent = 'TACTICAL SUPPLY';
    elements.shopTitle.textContent = '작전 지원 보급';
    elements.shopProductGrid.innerHTML = supportPackProductMarkup();
  } else {
    elements.shopEyebrow.textContent = 'ITEM INVENTORY';
    elements.shopTitle.textContent = '보유 아이템';
    elements.shopInventoryGrid.innerHTML = Object.keys(SUPPORT_ITEMS).map(shopItemMarkup).join('');
  }
  renderShopBuff();
  renderShopDetail();
  window.lucide?.createIcons();
}

function showCardPackResults(packKey, cardIds, paidPoints, ticket = false) {
  const grouped = cardIds.reduce((map, id) => map.set(id, (map.get(id) ?? 0) + 1), new Map());
  const layout = cardResultGridLayout(cardIds.length);
  elements.shopResultTitle.textContent = `${PACKS[packKey].name} 개봉`;
  elements.shopResultSummary.textContent = `${cardIds.length}장 획득 · ${ticket ? '교환권 사용' : `${number.format(paidPoints)}P 사용`} · ${grouped.size}종`;
  elements.shopResultGrid.dataset.resultType = 'cards';
  elements.shopResultGrid.classList.toggle('bulk', layout.bulk);
  elements.shopResultGrid.style.setProperty('--result-columns', layout.columns);
  elements.shopResultGrid.style.setProperty('--result-card-width', layout.cardWidth);
  elements.shopResultGrid.innerHTML = cardIds.map((id) => {
    const card = cardsById.get(id);
    return `<article class="shop-result-card card-visual" style="--rarity:${RARITIES[card.rarity].color}"><img class="card-photo" src="${imagePath(card)}" alt=""><div class="shop-result-shade"></div>${cardVisualChrome(card)}<span class="shop-result-name">${card.member}</span></article>`;
  }).join('');
  elements.shopResultDialog.showModal();
}

function showSupportResults(itemIds, paidPoints) {
  elements.shopResultTitle.textContent = `${SUPPORT_PACK.name} 결과`;
  elements.shopResultSummary.textContent = `${itemIds.length}개 획득 · ${number.format(paidPoints)}P 사용`;
  elements.shopResultGrid.dataset.resultType = 'items';
  elements.shopResultGrid.classList.remove('bulk');
  elements.shopResultGrid.style.removeProperty('--result-columns');
  elements.shopResultGrid.style.removeProperty('--result-card-width');
  elements.shopResultGrid.innerHTML = itemIds.map((itemId) => {
    const item = SUPPORT_ITEMS[itemId];
    return `<article class="shop-result-item"><i data-lucide="${ITEM_ICONS[item.category] ?? 'box'}"></i><b>${item.name}</b><span>${item.effect}</span></article>`;
  }).join('');
  window.lucide?.createIcons();
  elements.shopResultDialog.showModal();
}

async function purchaseCardPack(packKey, amount = 1, useTicketId = null, raceOverride = null, triggerButton = null) {
  return runUiOperation('purchasePack', triggerButton, async () => {
    if (fxController?.active) return;
    fxController?.unlockAudio();
    const pack = PACKS[packKey];
    if (!pack) return;
    const cost = useTicketId ? 0 : pack.price * amount;
    const packRace = packKey === 'race' ? raceOverride ?? selectedShopRace : null;
    if (remoteMode) {
      const response = useTicketId
        ? await executeServerCommand(GAME_COMMAND_TYPES.USE_SUPPORT_ITEM, {
          itemId: useTicketId, targetCardId: null, race: packKey === 'race' ? packRace : null,
        })
        : await executeServerCommand(GAME_COMMAND_TYPES.PURCHASE_PACK, {
          productId: packKey, quantity: amount, race: packRace,
        });
      if (!response?.ok) return response;
      const cardIds = (response.result?.cards ?? []).map((entry) => entry.cardId ?? entry);
      const openingPackImage = shopPackImage(packKey, packRace);
      const openingPackName = packKey === 'race' ? `${packRace} ${pack.name}` : pack.name;
      const openingCards = cardIds.map((id) => {
        const card = cardsById.get(id);
        return { image: imagePath(card), rarity: card.rarity, color: RARITIES[card.rarity].color, name: card.member, rank: RARITY_ORDER.indexOf(card.rarity) };
      });
      renderHeader();
      renderShop();
      await fxController?.playPackOpening({ image: openingPackImage, name: openingPackName, cards: openingCards, totalCount: cardIds.length });
      liveTickerController?.pushCardDraws(cardIds.map((id) => cardsById.get(id)).filter(Boolean));
      showCardPackResults(packKey, cardIds, response.result?.spentPoints ?? 0, Boolean(useTicketId));
      return response;
    }
    if (useTicketId && (state.supportItems[useTicketId] ?? 0) <= 0) return showToast('교환권 없음');
    if (state.points < cost) return showToast('포인트 부족');
    const cardIds = [];
    for (let index = 0; index < amount; index += 1) {
      cardIds.push(...drawCardPack(packKey, cards, { race: packRace, random: gameService.random }));
    }
    const granted = addCardResults(state.cardCopies, state.collectionRecords, cardIds);
    state.cardCopies = granted.copies;
    state.collectionRecords = granted.collectionRecords;
    state.points -= cost;
    if (useTicketId) state.supportItems[useTicketId] -= 1;
    state.shopTransactions += 1;
    const openingPackImage = shopPackImage(packKey, packRace);
    const openingPackName = packKey === 'race' ? `${packRace} ${pack.name}` : pack.name;
    const openingCards = cardIds.map((id) => {
      const card = cardsById.get(id);
      return {
        image: imagePath(card),
        rarity: card.rarity,
        color: RARITIES[card.rarity].color,
        name: card.member,
        rank: RARITY_ORDER.indexOf(card.rarity),
      };
    });
    gameService.purchasePack(state);
    renderHeader();
    renderShop();
    await fxController?.playPackOpening({
      image: openingPackImage,
      name: openingPackName,
      cards: openingCards,
      totalCount: cardIds.length,
    });
    liveTickerController?.pushCardDraws(cardIds.map((id) => cardsById.get(id)).filter(Boolean));
    showCardPackResults(packKey, cardIds, cost, Boolean(useTicketId));
  });
}

function purchaseSupportPack(amount = 1, triggerButton = null) {
  return runUiOperation('purchaseSupportPack', triggerButton, async () => {
    if (remoteMode) {
      const response = await executeServerCommand(GAME_COMMAND_TYPES.PURCHASE_SUPPORT_PACK, { quantity: amount });
      if (!response?.ok) return response;
      renderHeader();
      renderShop();
      showSupportResults(response.result?.items ?? [], response.result?.spentPoints ?? 0);
      return response;
    }
    const cost = amount === 10 ? SUPPORT_PACK.tenPrice : SUPPORT_PACK.price;
    if (state.points < cost) return showToast('포인트 부족');
    const itemIds = drawSupportPack(amount, gameService.random);
    state.supportItems = addSupportResults(state.supportItems, itemIds);
    state.points -= cost;
    state.shopTransactions += 1;
    gameService.purchasePack(state);
    renderHeader();
    renderShop();
    showSupportResults(itemIds, cost);
  });
}

async function activateShopItem(itemId) {
  const item = SUPPORT_ITEMS[itemId];
  if (!item) return;
  if (item.cardExp) {
    showScreen('enhance');
    showToast('강화 화면에서 EXP 포션을 사용할 카드를 선택하세요');
    return;
  }
  if (item.pack) {
    purchaseCardPack(item.pack, 1, itemId);
    return;
  }
  if (remoteMode) {
    return runUiOperation('useSupportItem', null, async () => {
      const response = await executeServerCommand(GAME_COMMAND_TYPES.USE_SUPPORT_ITEM, { itemId, targetCardId: null, race: null });
      if (!response?.ok) return response;
      renderHeader();
      renderShop();
      showToast(`${item.name} 사용`);
      return response;
    });
  }
  const result = useSupportItem(state, itemId, gameService.now());
  if (!result.used) return showToast(result.reason);
  state = result.state;
  gameService.persistSnapshot(state);
  renderHeader();
  renderShop();
  showToast(result.reason);
}

async function useSelectedCardExpPotion() {
  const card = selectedEnhancementCard();
  if (!card) return showToast('EXP를 지급할 카드를 선택하세요');
  if (remoteMode) {
    return runUiOperation('useSupportItem', elements.cardExpPotionButton, async () => {
      const response = await executeServerCommand(GAME_COMMAND_TYPES.USE_SUPPORT_ITEM, {
        itemId: 'cardExpPotion', targetCardId: card.id, race: null,
      });
      if (!response?.ok) return response;
      renderEnhancement();
      showToast(`${card.member} · 카드 EXP +${number.format(response.result?.cardExpGained ?? 0)}`);
      return response;
    });
  }
  const result = useCardExpPotion(state, card.id, cardExpRequired(card.enhancement));
  if (!result.used) return showToast(result.reason);
  state = result.state;
  gameService.persistSnapshot(state);
  renderEnhancement();
  showToast(`${card.member} · ${result.reason}`);
}

function releaseHeavyScreenDom(screen) {
  if (screen === 'collection') {
    elements.collectionCardGrid.replaceChildren();
    elements.collectionSetList.replaceChildren();
    elements.collectionSelected.replaceChildren();
  } else if (screen === 'enhance') {
    elements.enhanceTargetList.replaceChildren();
    elements.enhanceMaterials.replaceChildren();
  }
}

function showScreen(screen) {
  if (!SCREEN_IDS.has(screen)) {
    const label = document.querySelector(`[data-screen="${screen}"] span`)?.textContent ?? screen;
    showToast(`${label}은 다음 제작 묶음`);
    return;
  }
  if (screen === 'worldboss' && !WORLD_BOSS_ENABLED) {
    showToast('월드보스 준비 중입니다');
    screen = SCREEN_IDS.has(activeScreen) && activeScreen !== 'worldboss' ? activeScreen : 'adventure';
  }
  const previousScreen = activeScreen;
  activeScreen = screen;
  if (window.location.hash !== `#${screen}`) {
    window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}#${screen}`);
  }
  battleToken += 1;
  battleRunning = false;
  elements.adventureScreen.hidden = screen !== 'adventure';
  elements.shopScreen.hidden = screen !== 'shop';
  elements.enhanceScreen.hidden = screen !== 'enhance';
  elements.collectionScreen.hidden = screen !== 'collection';
  elements.worldBossScreen.hidden = screen !== 'worldboss';
  elements.minigameScreen.hidden = screen !== 'minigame';
  elements.rankingScreen.hidden = screen !== 'ranking';
  worldBossController?.setActive(screen === 'worldboss');
  document.querySelectorAll('.nav-item').forEach((button) => button.classList.toggle('active', button.dataset.screen === screen));
  if (screen === 'shop') renderShop();
  else if (screen === 'enhance') renderEnhancement();
  else if (screen === 'collection') renderCollection();
  else if (screen === 'worldboss') worldBossController?.render();
  else if (screen === 'minigame') miniGameController?.render();
  else if (screen === 'ranking') rankingController?.render();
  else {
    renderAll();
    if (state.autoBattle) setTimeout(runBattle, 350);
  }
  if (previousScreen !== screen) releaseHeavyScreenDom(previousScreen);
}

async function toggleEnhancementLock() {
  const card = selectedEnhancementCard();
  if (!card) return;
  if (remoteMode) {
    return runUiOperation('setCardLock', elements.enhanceLockButton, async () => {
      const response = await executeServerCommand(GAME_COMMAND_TYPES.SET_CARD_LOCK, { cardId: card.id, locked: !state.cardLocks[card.id] });
      if (!response?.ok) return response;
      enhancementResult = null;
      renderEnhancement();
      return response;
    });
  }
  state.cardLocks[card.id] = !state.cardLocks[card.id];
  gameService.persistSnapshot(state);
  enhancementResult = null;
  renderEnhancement();
  showToast(state.cardLocks[card.id] ? '카드 잠금 완료' : '카드 잠금 해제');
}

function prepareEnhancementAttempt() {
  if (fxController?.active) return;
  const card = selectedEnhancementCard();
  if (!card) return;
  const materials = getMaterialSelection(card);
  const gate = getEnhancementGate(card, materials, state.points, selectedBooster, state.supportItems);
  if (!gate.ready) {
    showToast(gate.reason);
    renderEnhancement();
    return;
  }
  const odds = getEnhancementOdds(card, selectedBooster);
  if (odds.target < 7) {
    executeEnhancementAttempt();
    return;
  }
  const pointCost = odds.target === 9 ? ENHANCEMENT.plusNinePointCost : 0;
  elements.enhanceConfirmTitle.textContent = `${card.member} ${enhancementLabel(odds.target)} 강화`;
  // nolevel-1: 파괴 = 강화 수치 0 리셋. 본카드 소멸 문구 제거.
  elements.enhanceConfirmSummary.textContent = '실패 시 재료가 소모되며, 파괴 판정에서는 강화 수치가 0으로 초기화됩니다. (본카드는 유지)';
  elements.enhanceConfirmSuccess.textContent = `${odds.success}%`;
  elements.enhanceConfirmDestroy.textContent = selectedBooster === 'destructionGuard' ? `${odds.destroy}% → 차단` : `${odds.destroy}%`;
  elements.enhanceConfirmMaterials.textContent = `${materials.rule.rarity} 중복 ${materials.rule.count}장`;
  elements.enhanceConfirmPoints.textContent = `${number.format(pointCost)} P`;
  elements.enhanceConfirmDialog.showModal();
}

async function executeEnhancementAttempt(triggerButton = elements.enhanceAttemptButton) {
  return runUiOperation('enhanceCard', triggerButton, async () => {
    if (fxController?.active) return;
    const card = selectedEnhancementCard();
    if (!card) return;
    const materials = getMaterialSelection(card);
    const gate = getEnhancementGate(card, materials, state.points, selectedBooster, state.supportItems);
    if (!gate.ready) {
      elements.enhanceConfirmDialog.close();
      showToast(gate.reason);
      renderEnhancement();
      return;
    }
    if (remoteMode) {
      const target = card.enhancement + 1;
      const response = await executeServerCommand(GAME_COMMAND_TYPES.ENHANCE_CARD, {
        cardId: card.id,
        targetEnhancement: target,
        materialCardIds: materials.selected,
        boosterId: selectedBooster === 'none' ? null : selectedBooster,
      });
      if (!response?.ok) return response;
      const outcome = response.result?.outcome ?? 'fail';
      enhancementResult = {
        type: outcome === 'success' ? 'success' : outcome === 'destroy' ? 'destroy' : 'fail',
        message: outcome === 'success'
          ? `강화 성공 · ${card.member} ${enhancementLabel(target)}`
          : outcome === 'destroy' ? `강화 파괴 · ${card.member} 강화 수치 초기화` : '강화 실패',
      };
      elements.enhanceConfirmDialog.close();
      selectedBooster = 'none';
      selectedMaterialOption = 0;
      renderHeader();
      renderEnhancement();
      await fxController?.playEnhancement({
        image: imagePath(card), rarity: card.rarity, color: RARITIES[card.rarity].color,
        name: card.member, target, outcome, message: enhancementResult.message,
      });
      if (outcome === 'success' && target === 9) liveTickerController?.pushNineStar(card);
      return response;
    }
    const result = resolveEnhancement(card, selectedBooster, gameService.random());
    const target = result.odds.target;
    state.cardCopies = consumeSelectedMaterials(state.cardCopies, materials.selected);
    if (target === 9) state.points -= ENHANCEMENT.plusNinePointCost;
    if (selectedBooster !== 'none') state.supportItems[selectedBooster] -= 1;
    state.enhancementAttempts += 1;

    if (result.outcome === 'success') {
      state.cardProgress[card.id] = applyEnhancementResult(card, result);
      enhancementResult = { type: 'success', message: `강화 성공 · ${card.member} ${enhancementLabel(target)}` };
    } else if (result.outcome === 'destroy') {
      // nolevel-1: 파괴 시 본카드는 유지, 강화 수치(exp 포함)만 0으로 리셋.
      state.cardProgress[card.id] = applyEnhancementResult(card, result);
      enhancementResult = { type: 'destroy', message: `강화 파괴 · ${card.member} 강화 수치 0으로 초기화 (본카드 유지)` };
    } else {
      enhancementResult = { type: 'fail', message: result.blocked ? '파괴 차단 성공 · 강화는 실패' : '강화 실패 · 경험치는 유지됨' };
    }

    ensureValidFormation();
    ensureValidRepresentativeCard();
    gameService.enhanceCard(state);
    elements.enhanceConfirmDialog.close();
    if ((state.cardCopies[card.id] ?? 0) <= 0) selectedEnhanceCardId = null;
    selectedBooster = 'none';
    selectedMaterialOption = 0;
    renderHeader();
    renderEnhancement();
    await fxController?.playEnhancement({
      image: imagePath(card),
      rarity: card.rarity,
      color: RARITIES[card.rarity].color,
      name: card.member,
      target,
      outcome: result.outcome,
      message: enhancementResult.message,
    });
    if (result.outcome === 'success' && target === 9) liveTickerController?.pushNineStar(card);
  });
}

function bindEvents() {
  if (sessionStorage.getItem('mail_wb_open_20260720_read') === 'true') {
    elements.mailBadge.hidden = true;
  }
  elements.profileCardButton.addEventListener('click', openRepresentativeCardDetail);
  elements.mailButton.addEventListener('click', () => {
    sessionStorage.setItem('mail_wb_open_20260720_read', 'true');
    elements.mailBadge.hidden = true;
    elements.mailDialog.showModal();
  });
  elements.soundToggleButton.addEventListener('click', () => {
    state.soundEnabled = state.soundEnabled === false;
    fxController?.setSoundEnabled(state.soundEnabled);
    if (state.soundEnabled) {
      fxController?.unlockAudio();
      fxController?.playUiCue();
    }
    gameService.persistSnapshot(state);
    renderHeader();
    window.lucide?.createIcons();
    showToast(state.soundEnabled ? '효과음 켜짐' : '효과음 꺼짐');
  });
  elements.apiLinkButton.addEventListener('click', () => {
    if (!bridgeStatus || !bridgeStatus.canUseDonationBridge) {
      showToast('스트리머 권한 확인 중이거나 권한이 없습니다. 우선 이동합니다.', 'warning');
    }
  });
  elements.logoutButton.addEventListener('click', async () => {
    if (!remoteMode || !confirm('로그아웃 하시겠습니까?')) return;
    elements.logoutButton.setAttribute('aria-busy', 'true');
    liveTickerController?.stop();
    const result = await remoteRuntime.auth.signOut();
    if (!result?.ok) {
      elements.logoutButton.removeAttribute('aria-busy');
      await liveTickerController?.start();
      showToast('로그아웃에 실패했습니다. 다시 시도하세요.');
      return;
    }
    window.location.replace(`${window.location.pathname}${window.location.search}`);
  });
  elements.autoBattleButton.addEventListener('click', async () => {
    if (state.autoBattle) {
      state.autoBattle = false;
      if (!remoteMode) gameService.persistSnapshot(state);
      renderHeader();
      return;
    }
    const activeRun = normalizeAdventureRun(state.adventureRun);
    if (!activeRun.active) {
      if (remoteMode) {
        const response = await runUiOperation('startAdventureRun', elements.autoBattleButton, () => (
          executeServerCommand(GAME_COMMAND_TYPES.START_ADVENTURE_RUN, {})
        ));
        if (!response?.ok) return;
        state.currentStage = 1;
      } else {
        const now = gameService.now();
        const runStatus = getAdventureRunLimitStatus(state.adventureRuns, now);
        if (runStatus.remaining <= 0) return showToast('4시간당 모험 3회 완료');
        state.adventureRuns = recordAdventureRun(state.adventureRuns, now);
        state.adventureRun = createAdventureRun(now);
        state.currentStage = 1;
      }
    }
    state.autoBattle = true;
    if (!remoteMode) gameService.persistSnapshot(state);
    renderHeader();
    if (!battleRunning) runBattle();
  });
  elements.formationButton.addEventListener('click', openFormation);
  elements.inventoryGrid.addEventListener('click', (event) => {
    const button = event.target.closest('[data-card-id]');
    if (button) toggleFormationCard(button.dataset.cardId);
  });
  elements.confirmFormation.addEventListener('click', confirmFormation);
  elements.clearFormation.addEventListener('click', clearFormationSelection);
  elements.quickBattleButton.addEventListener('click', () => openRewardDialog('quick'));
  elements.claimButton.addEventListener('click', () => openRewardDialog('offline'));
  elements.confirmReward.addEventListener('click', confirmReward);
  elements.formationDialog.addEventListener('close', () => {
    if (activeScreen === 'adventure' && state.autoBattle && !battleRunning) setTimeout(runBattle, 350);
  });
  elements.rewardDialog.addEventListener('close', () => {
    if (activeScreen === 'adventure' && state.autoBattle && !battleRunning) setTimeout(runBattle, 350);
  });
  document.querySelectorAll('.nav-item').forEach((button) => {
    if (!WORLD_BOSS_ENABLED && button.dataset.screen === 'worldboss') {
      button.classList.add('nav-soon');
      const label = button.querySelector('span');
      if (label) label.textContent = '준비중';
    }
    button.addEventListener('click', () => showScreen(button.dataset.screen));
  });
  elements.enhanceTargetList.addEventListener('click', (event) => {
    const button = event.target.closest('[data-enhance-card-id]');
    if (!button) return;
    selectedEnhanceCardId = button.dataset.enhanceCardId;
    selectedMaterialOption = 0;
    selectedBooster = 'none';
    enhancementResult = null;
    renderEnhancement();
  });
  document.querySelectorAll('[data-enhance-filter]').forEach((button) => {
    button.addEventListener('click', () => {
      enhanceFilter = button.dataset.enhanceFilter;
      renderEnhancement();
    });
  });
  elements.enhanceMaterialOptions.addEventListener('click', (event) => {
    const button = event.target.closest('[data-material-option]');
    if (!button) return;
    selectedMaterialOption = Number(button.dataset.materialOption);
    enhancementResult = null;
    renderEnhancement();
  });
  elements.enhanceSupports.addEventListener('click', (event) => {
    const button = event.target.closest('[data-booster]');
    if (!button || button.disabled) return;
    selectedBooster = button.dataset.booster;
    enhancementResult = null;
    renderEnhancement();
  });
  elements.enhanceLockButton.addEventListener('click', toggleEnhancementLock);
  elements.cardExpPotionButton.addEventListener('click', useSelectedCardExpPotion);
  elements.enhanceAttemptButton.addEventListener('click', prepareEnhancementAttempt);
  elements.confirmEnhanceAttempt.addEventListener('click', () => executeEnhancementAttempt(elements.confirmEnhanceAttempt));
  elements.collectionCardGrid.addEventListener('click', (event) => {
    const button = event.target.closest('[data-collection-card-id]');
    if (!button) return;
    selectedCollectionCardId = button.dataset.collectionCardId;
    renderCollection();
    openCardDetail(selectedCollectionCardId);
  });
  elements.cardDetailLockButton.addEventListener('click', toggleCardDetailLock);
  elements.cardDetailRepresentativeButton.addEventListener('click', setRepresentativeCardFromDetail);
  elements.cardDetailBody.addEventListener('pointermove', updateCardDetailTilt);
  elements.cardDetailBody.addEventListener('pointerout', resetCardDetailTilt);
  elements.collectionOwnershipFilter.addEventListener('click', (event) => {
    const button = event.target.closest('[data-collection-owned]');
    if (!button) return;
    collectionOwnership = button.dataset.collectionOwned;
    renderCollection();
  });
  elements.collectionRaceFilter.addEventListener('click', (event) => {
    const button = event.target.closest('[data-collection-race]');
    if (!button) return;
    collectionRace = button.dataset.collectionRace;
    renderCollection();
  });
  elements.collectionRarityFilter.addEventListener('click', (event) => {
    const button = event.target.closest('[data-collection-rarity]');
    if (!button) return;
    collectionRarity = button.dataset.collectionRarity;
    renderCollection();
  });
  elements.collectionSetTabs.addEventListener('click', (event) => {
    const button = event.target.closest('[data-collection-set]');
    if (!button) return;
    collectionSetType = button.dataset.collectionSet;
    renderCollection();
  });

  elements.dismantleButton.addEventListener('click', () => {
    dismantleRarity = null;
    renderDismantlePreview();
    elements.dismantleDialog.showModal();
  });

  elements.dismantleCancelButton.addEventListener('click', () => {
    elements.dismantleDialog.close();
  });

  elements.dismantleRaritySelect.addEventListener('click', (event) => {
    const button = event.target.closest('button');
    if (!button) return;
    dismantleRarity = button.dataset.dismantleRarity;
    renderDismantlePreview();
  });

  elements.dismantleConfirmButton.addEventListener('click', async () => {
    if (!dismantleRarity || elements.dismantleConfirmButton.disabled) return;
    const isHighRarity = ['S', 'SS', 'SSS'].includes(dismantleRarity);
    if (isHighRarity && !confirm(`정말로 ${dismantleRarity} 등급 카드를 분해하시겠습니까? 이 작업은 되돌릴 수 없습니다.`)) return;

    elements.dismantleConfirmButton.disabled = true;
    const payload = { rarity: dismantleRarity };
    
    if (remoteMode) {
      await serverCommands.dismantleCards(payload);
    } else {
      // Local fallback logic for test
      const rule = DISMANTLE_RULES.dropRates[dismantleRarity];
      let dismantledCount = 0;
      let gainedPotions = 0;
      let gainedPoints = 0;
      for (const card of cards) {
        if (card.rarity !== dismantleRarity) continue;
        const progress = state.cardProgress[card.id];
        if (progress?.locked) continue;
        const copies = state.inventory[card.id] ?? 0;
        if (copies > 1) {
          const count = copies - 1;
          dismantledCount += count;
          state.inventory[card.id] = 1;
          for (let i = 0; i < count; i++) {
            if (gameService.random() < rule.potionRate) gainedPotions++;
            if (gameService.random() < rule.pointsRate) gainedPoints += rule.points;
          }
        }
      }
      if (dismantledCount > 0) {
        state.supportItems.cardExpPotionLarge = (state.supportItems.cardExpPotionLarge ?? 0) + gainedPotions;
        state.points += gainedPoints;
        const items = [];
        if (gainedPotions > 0) items.push(`대형 경험치 포션 x${gainedPotions}`);
        if (gainedPoints > 0) items.push(`${number.format(gainedPoints)} P`);
        
        elements.dismantleResult.hidden = false;
        elements.dismantleResult.innerHTML = `<p>총 ${dismantledCount}장 분해 완료</p><ul>${items.map(item => `<li>${item} 획득</li>`).join('') || '<li>획득한 아이템이 없습니다.</li>'}</ul>`;
        renderCollection();
        renderHeader();
      }
    }
  });
  elements.shopTabs.addEventListener('click', (event) => {
    const button = event.target.closest('[data-shop-tab]');
    if (!button) return;
    shopTab = button.dataset.shopTab;
    if (shopTab === 'cards' && !SHOP_CARD_PRODUCTS[selectedShopProduct]) selectedShopProduct = 'general';
    renderShop();
  });
  elements.shopRaceSelector.addEventListener('click', (event) => {
    const button = event.target.closest('[data-shop-race]');
    if (!button) return;
    selectedShopRace = button.dataset.shopRace;
    renderShop();
  });
  elements.shopProductGrid.addEventListener('click', (event) => {
    const cardPurchase = event.target.closest('[data-buy-card-pack]');
    if (cardPurchase) {
      purchaseCardPack(cardPurchase.dataset.buyCardPack, Number(cardPurchase.dataset.buyCount), null, cardPurchase.dataset.buyRace || null, cardPurchase);
      return;
    }
    const supportPurchase = event.target.closest('[data-buy-support]');
    if (supportPurchase) {
      purchaseSupportPack(Number(supportPurchase.dataset.buySupport), supportPurchase);
      return;
    }
    const product = event.target.closest('[data-shop-product]');
    if (!product || product.dataset.shopProduct === 'support') return;
    selectedShopProduct = product.dataset.shopProduct;
    selectedShopRace = SHOP_CARD_PRODUCTS[selectedShopProduct]?.race ?? selectedShopRace;
    renderShop();
  });
  elements.shopInventoryGrid.addEventListener('click', (event) => {
    const button = event.target.closest('[data-use-shop-item]');
    if (button && !button.disabled) activateShopItem(button.dataset.useShopItem);
  });
  elements.shopResultDialog.addEventListener('click', (event) => {
    if (event.button === 0 && elements.shopResultDialog.open) elements.shopResultDialog.close();
  });
}

function startTimedUpdates() {
  let tickCount = 0;
  setInterval(() => {
    tickCount += 1;
    synchronizeTimedState();
    renderHeader();
    renderRewardReadout();
    if (activeScreen === 'shop') renderShopBuff();
    if (activeScreen === 'worldboss') worldBossController?.tick();
    // Nav badge nudge: check reward availability even when off the world boss
    // screen, since claiming is manual and the results window is only 30 minutes.
    else if (tickCount % 60 === 0) void worldBossController?.checkRewardAvailability();
  }, 1000);
}

async function init() {
  cacheElements();
  elements.systemStateRetry.addEventListener('click', () => {
    if (elements.systemStateLayer.dataset.state === 'conflict') return window.location.reload();
    if (requestCoordinator.hasRetryableFailure()) requestCoordinator.retryLast();
    else window.location.reload();
  });
  setSystemState('loading');
  fxController = createFxController({ soundEnabled: state.soundEnabled !== false, random: gameService.random });
  try {
    const response = await fetch('data/renewal-cards.json');
    if (!response.ok) throw new Error(`Card data request failed: ${response.status}`);
    cards = await response.json();
    cardsById = new Map(cards.map((card) => [card.id, card]));
    if (remoteMode) await requireRemoteSnapshot();
    if (remoteMode) {
      const status = await gameService.getBridgeStatus();
      if (status?.ok !== false) bridgeStatus = status;
    }
    if (elements.apiLinkButton) elements.apiLinkButton.hidden = remoteMode && !bridgeStatus.canUseDonationBridge;
    miniGameController = createMiniGameController({
      cards,
      getState: () => state,
      clock: gameService,
      persist: (operation) => runUiOperation(operation, null, () => { gameService[operation](state); renderHeader(); }),
      serverCommands: remoteMode ? {
        startMinigame: (payload) => runUiOperation('startMinigame', elements.miniGameStartButton, () => (
          executeServerCommand(GAME_COMMAND_TYPES.START_MINIGAME, payload)
        )),
        finishMinigame: (payload) => runUiOperation('finishMinigame', null, () => (
          executeServerCommand(GAME_COMMAND_TYPES.FINISH_MINIGAME, payload)
        )),
      } : null,
      showToast,
    });
    worldBossController = createWorldBossController({
      getState: () => state,
      getFormation: formationCards,
      getBonuses: currentCombatBonuses,
      clock: gameService,
      random: gameService.random,
      persist: (operation) => runUiOperation(operation, null, () => { gameService[operation](state); renderHeader(); }),
      serverCommands: remoteMode ? {
        getWorldBossStatus: () => gameService.getWorldBossStatus(),
        subscribeWorldBoss: (onChange) => remoteRuntime.subscribeWorldBoss(onChange),
        attackWorldBoss: (payload) => runUiOperation('attackWorldBoss', elements.worldBossAttackButton, () => (
          executeServerCommand(GAME_COMMAND_TYPES.ATTACK_WORLD_BOSS, payload)
        )),
        dismantleCards: async (payload) => {
          const result = await executeServerCommand(GAME_COMMAND_TYPES.DISMANTLE_CARDS, payload);
          if (result && result.dismantledCount > 0) {
            const items = [];
            if (result.gainedPotions > 0) items.push(`대형 경험치 포션 x${result.gainedPotions}`);
            if (result.gainedPoints > 0) items.push(`${number.format(result.gainedPoints)} P`);
            elements.dismantleResult.hidden = false;
            elements.dismantleResult.innerHTML = `<p>총 ${result.dismantledCount}장 분해 완료</p><ul>${items.map(item => `<li>${item} 획득</li>`).join('') || '<li>획득한 아이템이 없습니다.</li>'}</ul>`;
            dismantleRarity = null;
            renderCollection();
          }
          return result;
        },
        claimWorldBossReward: (payload) => runUiOperation('claimWorldBossReward', elements.worldBossRewardButton, () => (
          executeServerCommand(GAME_COMMAND_TYPES.CLAIM_WORLD_BOSS_REWARD, payload)
        )),
      } : null,
      showToast,
      onRewardAvailability: (available) => {
        if (elements.worldBossNavBadge) elements.worldBossNavBadge.hidden = !available;
      },
    });
    rankingController = createRankingController({
      cards,
      getState: () => state,
      getFormation: formationCards,
      getCombatPower: () => computeFormationPower(formationCards(), currentCombatBonuses()),
      gameService,
    });
    liveTickerController = createLiveTickerController({
      runtime: remoteRuntime,
      getNickname: () => state.nickname,
      now: gameService.now,
    });
    if (!remoteMode) {
      ensureCardProgress();
      applyLocalTestProfile(state, cards, window.location.hostname);
      ensureValidAdventureProgress();
      ensureValidFormation();
      ensureValidRepresentativeCard();
    }
    assertValidGameState(state, { cardIds: cardsById.keys(), requireOwnedCards: true });
    if (!remoteMode) gameService.persistSnapshot(state);
    renderAll();
    bindEvents();
    showScreen(activeScreen);
    if (elements.logoutButton) elements.logoutButton.hidden = !remoteMode;
    // 모바일에서 로그인 후 게임 진입 시 가로모드/전체화면 가이드 표시.
    showOrientGuideIfNeeded();
    await liveTickerController.start();
    startTimedUpdates();
    if (activeScreen !== 'worldboss') void worldBossController?.checkRewardAvailability();
    const canPreviewState = ['localhost', '127.0.0.1'].includes(window.location.hostname) && SYSTEM_STATES[systemStatePreview];
    setSystemState(canPreviewState ? systemStatePreview : null);
  } catch (error) {
    console.error('[init] fatal:', error);
    elements.battleState.textContent = `초기화 실패: ${error?.message ?? error}`;
    setSystemState('network');
  }
}

// Phase 1 점검 가드: runtime-config.js가 점검 모드를 켰으면 앱 초기화를 중단한다.
// 점검 오버레이는 runtime-config.js에서 이미 DOM에 주입했다.
const __runtimeConfig = globalThis.__CARD_GACHA_CONFIG__;
if (__runtimeConfig?.maintenanceActive) {
  // 점검 중: 게임 셸 숨김 처리(혹시 runtime-config보다 늦게 실행된 경우 대비)
  const shell = document.getElementById('gameShell');
  if (shell) shell.style.display = 'none';
} else {
  init();
}
