import { SUPPORT_ITEMS } from './config.js';
import { createDefaultState } from './storage.js';
import { validateGameState } from './state-schema.js';

export const SEASON2_IMPORT_RULES = Object.freeze({
  initialPoints: 5000,
  preserveStreamerAccountsWithoutCards: true,
  rankRewards: Object.freeze([
    { from: 1, to: 10, points: 30000 },
    { from: 11, to: 20, points: 20000 },
    { from: 21, to: 30, points: 15000 },
    { from: 31, to: 40, points: 10000 },
    { from: 41, to: 50, points: 5000 },
  ]),
});

const isRecord = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

function issue(issues, severity, code, message, context = {}) {
  issues.push({ severity, code, message, ...context });
}

function duplicates(values) {
  const seen = new Set();
  const duplicate = new Set();
  values.filter((value) => value !== null && value !== undefined && value !== '').forEach((value) => {
    if (seen.has(value)) duplicate.add(value);
    seen.add(value);
  });
  return [...duplicate];
}

function blankSupportItems() {
  return Object.fromEntries(Object.keys(SUPPORT_ITEMS).map((itemId) => [itemId, 0]));
}

function rankingRows(snapshot) {
  if (Array.isArray(snapshot)) return snapshot;
  if (isRecord(snapshot) && Array.isArray(snapshot.rows)) return snapshot.rows;
  return [];
}

export function season1RankReward(rank) {
  const value = Math.floor(Number(rank) || 0);
  return SEASON2_IMPORT_RULES.rankRewards.find((tier) => value >= tier.from && value <= tier.to)?.points ?? 0;
}

export function analyzeSeason1RankingSnapshot(snapshot) {
  const rows = rankingRows(snapshot);
  const issues = [];
  if (rows.length !== 50) issue(issues, 'error', 'TOP50_ROW_COUNT', '최종 랭킹 스냅샷은 정확히 50행 필요', { count: rows.length });
  duplicates(rows.map((row) => row.rank)).forEach((value) => issue(issues, 'error', 'DUPLICATE_RANK', '중복 순위', { value }));
  duplicates(rows.map((row) => row.user_id)).forEach((value) => issue(issues, 'error', 'DUPLICATE_RANK_USER', '중복 랭커 계정', { value }));
  rows.forEach((row) => {
    if (!Number.isInteger(row.rank) || row.rank < 1 || row.rank > 50) issue(issues, 'error', 'INVALID_RANK', '순위는 1~50 정수', { value: row.rank });
    if (typeof row.user_id !== 'string' || !row.user_id) issue(issues, 'error', 'INVALID_RANK_USER', '랭커 user_id 필요', { rank: row.rank });
  });
  for (let rank = 1; rank <= 50; rank += 1) {
    if (!rows.some((row) => row.rank === rank)) issue(issues, 'error', 'MISSING_RANK', '누락 순위', { value: rank });
  }
  return {
    ok: !issues.some((entry) => entry.severity === 'error'),
    issues,
    rows,
    summary: {
      rows: rows.length,
      rewardTotal: rows.reduce((sum, row) => sum + season1RankReward(row.rank), 0),
      rewardCounts: Object.fromEntries(SEASON2_IMPORT_RULES.rankRewards.map((tier) => [
        `${tier.from}-${tier.to}`,
        rows.filter((row) => row.rank >= tier.from && row.rank <= tier.to).length,
      ])),
    },
  };
}

function buildImportedState(user, rank, importedAt) {
  const state = createDefaultState(importedAt);
  const rankRewardPoints = season1RankReward(rank);
  state.nickname = user.nickname.trim();
  state.actionEnergy = state.maxActionEnergy;
  state.lastEnergyAt = importedAt;
  state.points = SEASON2_IMPORT_RULES.initialPoints + rankRewardPoints;
  state.currentStage = 1;
  state.clearedStage = 0;
  state.pendingPoints = 0;
  state.lastRewardAt = importedAt;
  state.quickBattle = { windowStartedAt: 0, count: 0 };
  state.adventureRuns = { windowStartedAt: 0, count: 0 };
  state.adventureRun = { active: false, currentStage: 1, clearedStages: 0, startedAt: 0 };
  state.cardProgress = {};
  state.cardCopies = {};
  state.cardLocks = {};
  state.collectionRecords = {};
  state.supportItems = blankSupportItems();
  state.activeBuffs = { cardExpStartAt: 0, cardExpEndAt: 0 };
  state.shopTransactions = 0;
  state.enhancementAttempts = 0;
  state.miniGames = {
    date: new Date(importedAt).toISOString().slice(0, 10),
    pointsEarned: 0,
    pointsEarnedByGame: { memory: 0, sumTen: 0, ladder: 0 },
    plays: 0,
    bestMemory: 0,
    bestSumTen: 0,
    bestLadder: 0,
  };
  state.worldBoss.attempts = 0;
  state.worldBoss.bestDamage = 0;
  state.worldBoss.totalDamage = 0;
  state.worldBoss.claimedTier = -1;
  state.worldBoss.lastDamage = 0;
  state.exMilestoneClaims = {};
  state.representativeCardId = null;
  state.formation = [];
  state.formationPresets = {};
  state.activeFormationPresetId = null;
  state.miniGameRuns = [];
  state.powerRanking = { seasonId: 'season-2', snapshotAt: 0, power: 0, rank: null, population: 0 };
  return { state, rankRewardPoints };
}

export function analyzeSeason1Export(source, cards, options = {}) {
  const importedAt = Number.isSafeInteger(options.importedAt) ? options.importedAt : Date.now();
  const sampleSize = Number.isInteger(options.sampleSize) ? Math.max(1, options.sampleSize) : 10;
  const issues = [];
  if (!isRecord(source)) return { ok: false, issues: [{ severity: 'error', code: 'INVALID_EXPORT', message: '내보내기 객체 필요' }] };
  const users = Array.isArray(source.users) ? source.users : [];
  const collection = Array.isArray(source.collection) ? source.collection : [];
  const serials = Array.isArray(source.cardSerials) ? source.cardSerials : [];
  const memberRewards = Array.isArray(source.memberRewards) ? source.memberRewards : [];
  const bridgeKeys = Array.isArray(source.bridgeKeys) ? source.bridgeKeys : [];
  const snapshotAnalysis = analyzeSeason1RankingSnapshot(options.rankingSnapshot ?? source.rankingSnapshot);
  issues.push(...snapshotAnalysis.issues);
  const usersById = new Map(users.map((user) => [user.id, user]));

  duplicates(bridgeKeys.map((row) => row?.soop_id)).forEach((value) => issue(issues, 'error', 'DUPLICATE_BRIDGE_SOOP_ID', 'Duplicate bridge SOOP ID', { value }));
  duplicates(bridgeKeys.map((row) => row?.key_hash)).forEach((value) => issue(issues, 'error', 'DUPLICATE_BRIDGE_KEY_HASH', 'Duplicate bridge key hash', { value }));

  duplicates(users.map((user) => user.id)).forEach((value) => issue(issues, 'error', 'DUPLICATE_USER_ID', '중복 사용자 ID', { value }));
  duplicates(users.map((user) => user.login_key_hash)).forEach((value) => issue(issues, 'error', 'DUPLICATE_LOGIN_HASH', '중복 로그인 키 해시', { value }));
  duplicates(users.map((user) => user.soop_id)).forEach((value) => issue(issues, 'error', 'DUPLICATE_SOOP_ID', '중복 SOOP ID', { value }));

  users.forEach((user) => {
    if (!isRecord(user) || typeof user.id !== 'string' || !user.id) issue(issues, 'error', 'INVALID_USER', '사용자 ID 필요');
    if (typeof user.nickname !== 'string' || !user.nickname.trim() || user.nickname.trim().length > 40) {
      issue(issues, 'error', 'INVALID_NICKNAME', '닉네임은 1~40자', { userId: user.id });
    }
    if (typeof user.login_key_hash !== 'string' || !/^[a-f0-9]{64}$/i.test(user.login_key_hash)) {
      issue(issues, 'error', 'INVALID_LOGIN_HASH', 'SHA-256 로그인 키 해시 필요', { userId: user.id });
    }
  });
  bridgeKeys.forEach((row) => {
    if (!isRecord(row) || typeof row.soop_id !== 'string' || !row.soop_id.trim()) {
      issue(issues, 'error', 'INVALID_BRIDGE_SOOP_ID', 'Bridge SOOP ID required');
    }
    if (typeof row?.key_hash !== 'string' || !/^[a-f0-9]{64}$/i.test(row.key_hash)) {
      issue(issues, 'error', 'INVALID_BRIDGE_KEY_HASH', 'Bridge SHA-256 key hash required', { soopId: row?.soop_id });
    }
    if (typeof row?.active !== 'boolean') {
      issue(issues, 'error', 'INVALID_BRIDGE_ACTIVE', 'Bridge active state must be boolean', { soopId: row?.soop_id });
    }
  });

  const cardTotals = new Map(users.map((user) => [user.id, 0]));
  collection.forEach((row) => {
    if (!usersById.has(row.user_id)) return issue(issues, 'error', 'ORPHAN_COLLECTION', '사용자 없는 카드 행', { userId: row.user_id, cardId: row.card_id });
    if (!Number.isSafeInteger(row.count) || row.count < 0) return issue(issues, 'error', 'INVALID_CARD_COUNT', '카드 수량은 0 이상 정수', { userId: row.user_id, cardId: row.card_id });
    cardTotals.set(row.user_id, (cardTotals.get(row.user_id) ?? 0) + row.count);
  });

  const streamerSoopIds = new Set(bridgeKeys.map((row) => row?.soop_id).filter(Boolean));
  const isStreamer = (user) => Boolean(user.soop_id && streamerSoopIds.has(user.soop_id));
  const eligibleUsers = users.filter((user) => (cardTotals.get(user.id) ?? 0) > 0 || isStreamer(user));
  const eligibleIds = new Set(eligibleUsers.map((user) => user.id));
  const rankByUser = new Map(snapshotAnalysis.rows.map((row) => [row.user_id, row.rank]));
  snapshotAnalysis.rows.forEach((row) => {
    if (!usersById.has(row.user_id)) issue(issues, 'error', 'RANK_USER_NOT_IN_EXPORT', '랭커 계정이 사용자 export에 없음', { rank: row.rank, userId: row.user_id });
    else if (!eligibleIds.has(row.user_id)) issue(issues, 'warning', 'RANK_USER_WITHOUT_CARDS_EXCLUDED', '카드 미개봉 랭커 계정은 시즌2 이관 제외', { rank: row.rank, userId: row.user_id });
  });

  const cardIds = cards.map((card) => card.id);
  const mappedAccounts = [];
  const mappedStates = [];
  eligibleUsers.forEach((user) => {
    if (issues.some((entry) => entry.severity === 'error' && entry.userId === user.id)) return;
    const rank = rankByUser.get(user.id) ?? null;
    const imported = buildImportedState(user, rank, importedAt);
    const validation = validateGameState(imported.state, { cardIds, requireOwnedCards: true });
    if (!validation.valid) {
      issue(issues, 'error', 'INVALID_MAPPED_STATE', validation.issues.slice(0, 5).map((entry) => `${entry.path}: ${entry.message}`).join('; '), { userId: user.id });
      return;
    }
    mappedAccounts.push({
      legacyUserId: user.id,
      nickname: user.nickname.trim(),
      soopId: user.soop_id ?? null,
      loginKeyHash: user.login_key_hash,
      createdAt: user.created_at ?? null,
      season1FinalRank: rank,
      rankRewardPoints: imported.rankRewardPoints,
      initialPoints: imported.state.points,
      isStreamer: isStreamer(user),
    });
    mappedStates.push({ legacyUserId: user.id, state: imported.state });
  });

  const retainedSoopIds = new Set(mappedAccounts.map((account) => account.soopId).filter(Boolean));
  const retainedBridgeKeys = bridgeKeys.filter((row) => retainedSoopIds.has(row?.soop_id));
  const orphanBridgeKeys = bridgeKeys.filter((row) => !users.some((user) => user.soop_id === row?.soop_id));
  orphanBridgeKeys.forEach((row) => issue(issues, 'error', 'ORPHAN_BRIDGE_KEY', 'Bridge key has no matching account', { soopId: row?.soop_id }));
  const retainedStreamerWithoutCards = eligibleUsers.filter((user) => isStreamer(user) && (cardTotals.get(user.id) ?? 0) === 0).length;
  const deletedNoCardNonStreamerUsers = users.filter((user) => !isStreamer(user) && (cardTotals.get(user.id) ?? 0) === 0).length;
  const mappedPoints = mappedStates.reduce((sum, entry) => sum + entry.state.points, 0);
  const rankBonusPoints = mappedAccounts.reduce((sum, account) => sum + account.rankRewardPoints, 0);
  const sourceCardCopies = [...cardTotals.values()].reduce((sum, count) => sum + count, 0);
  const sampleIds = [...mappedAccounts]
    .sort((left, right) => String(left.createdAt ?? '').localeCompare(String(right.createdAt ?? '')) || left.legacyUserId.localeCompare(right.legacyUserId))
    .slice(0, sampleSize)
    .map((account) => account.legacyUserId);

  return {
    ok: !issues.some((entry) => entry.severity === 'error'),
    importedAt,
    summary: {
      sourceUsers: users.length,
      retainedUsers: mappedAccounts.length,
      deletedNoCardUsers: deletedNoCardNonStreamerUsers,
      deletedNoCardNonStreamerUsers,
      retainedStreamerWithoutCards,
      initialPointsPerUser: SEASON2_IMPORT_RULES.initialPoints,
      basePointTotal: mappedAccounts.length * SEASON2_IMPORT_RULES.initialPoints,
      rankBonusPoints,
      mappedPoints,
      sourceCardCopies,
      mappedCardCopies: 0,
      clearedCollectionRows: collection.length,
      discardedSerials: serials.length,
      discardedMemberRewardRows: memberRewards.length,
      retainedBridgeKeyRows: retainedBridgeKeys.length,
      orphanBridgeKeyRows: orphanBridgeKeys.length,
      rankingSnapshotRows: snapshotAnalysis.rows.length,
      errors: issues.filter((entry) => entry.severity === 'error').length,
      warnings: issues.filter((entry) => entry.severity === 'warning').length,
    },
    sampleIds,
    issues,
    mapped: {
      accounts: mappedAccounts,
      states: mappedStates,
      serials: [],
      memberRewardAudit: [],
      bridgeKeys: retainedBridgeKeys.map((row) => ({ ...row })),
    },
  };
}
