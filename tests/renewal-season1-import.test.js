import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  SEASON2_IMPORT_RULES,
  analyzeSeason1Export,
  analyzeSeason1RankingSnapshot,
  season1RankReward,
} from '../src/renewal/season1-import.js';

const cards = JSON.parse(await readFile(new URL('../data/renewal-cards.json', import.meta.url), 'utf8'));
const users = Array.from({ length: 60 }, (_, index) => ({
  id: `legacy-user-${String(index + 1).padStart(2, '0')}`,
  nickname: `테스트계정${index + 1}`,
  soop_id: index < 10 ? `soop_${index + 1}` : index === 59 ? 'streamer_3' : null,
  login_key_hash: index.toString(16).padStart(64, '0'),
  points: (index + 1) * 1000,
  created_at: `2026-07-${String(index % 28 + 1).padStart(2, '0')}T00:00:00Z`,
}));
const collection = users.slice(0, 55).map((user, index) => ({
  user_id: user.id,
  card_id: index === 54 ? 'season1-card-not-in-season2' : 'kimyunhwan-2',
  count: index % 3 + 1,
  first_at: '2026-07-01T00:00:00Z',
}));
const cardSerials = collection.map((row, index) => ({
  user_id: row.user_id,
  card_id: row.card_id,
  serial: index + 1,
  acquired_via: 'pack',
}));
const rankingSnapshot = {
  snapshot: 'season1-final-top50',
  rows: users.slice(0, 50).map((user, index) => ({
    rank: index + 1,
    user_id: user.id,
    nickname: user.nickname,
    ranking_score: 1_000_000 - index * 1000,
  })),
};
const source = {
  users,
  collection,
  cardSerials,
  memberRewards: users.slice(0, 3).map((user) => ({ user_id: user.id, member: '김윤환' })),
  bridgeKeys: [users[0], users[1], users[59]].map((user, index) => ({
    soop_id: user.soop_id,
    key_hash: `${index + 1}`.repeat(64),
    active: index !== 2,
    created_at: `2026-06-0${index + 1}T00:00:00Z`,
    last_used_at: index === 0 ? '2026-07-18T00:00:00Z' : null,
  })),
};

assert.equal(SEASON2_IMPORT_RULES.initialPoints, 5000);
assert.equal(season1RankReward(1), 30000);
assert.equal(season1RankReward(10), 30000);
assert.equal(season1RankReward(11), 20000);
assert.equal(season1RankReward(21), 15000);
assert.equal(season1RankReward(31), 10000);
assert.equal(season1RankReward(41), 5000);
assert.equal(season1RankReward(51), 0);
const rankingReport = analyzeSeason1RankingSnapshot(rankingSnapshot);
assert.equal(rankingReport.ok, true, JSON.stringify(rankingReport.issues));
assert.equal(rankingReport.summary.rewardTotal, 800_000);

const report = analyzeSeason1Export(source, cards, {
  importedAt: 1_784_246_400_000,
  sampleSize: 10,
  rankingSnapshot,
});
assert.equal(report.ok, true, JSON.stringify(report.issues));
assert.equal(report.summary.sourceUsers, 60);
assert.equal(report.summary.retainedUsers, 56);
assert.equal(report.summary.deletedNoCardUsers, 4);
assert.equal(report.summary.deletedNoCardNonStreamerUsers, 4);
assert.equal(report.summary.retainedStreamerWithoutCards, 1);
assert.equal(report.summary.basePointTotal, 280_000);
assert.equal(report.summary.rankBonusPoints, 800_000);
assert.equal(report.summary.mappedPoints, 1_080_000);
assert.equal(report.summary.mappedCardCopies, 0);
assert.equal(report.summary.clearedCollectionRows, 55);
assert.equal(report.summary.discardedSerials, 55);
assert.equal(report.summary.discardedMemberRewardRows, 3);
assert.equal(report.summary.retainedBridgeKeyRows, 3);
assert.equal(report.summary.orphanBridgeKeyRows, 0);
assert.equal(report.sampleIds.length, 10);
assert.equal(report.mapped.accounts.find((account) => account.season1FinalRank === 1).initialPoints, 35_000);
assert.equal(report.mapped.accounts.find((account) => account.season1FinalRank === 50).initialPoints, 10_000);
assert.equal(report.mapped.accounts.find((account) => account.legacyUserId === users[50].id).initialPoints, 5_000);
assert.equal(report.mapped.accounts.find((account) => account.legacyUserId === users[59].id).isStreamer, true);
assert.ok(report.mapped.states.every((entry) => (
  entry.state.actionEnergy === entry.state.maxActionEnergy
  && entry.state.clearedStage === 0
  && entry.state.points >= 5000
  && Object.keys(entry.state.cardCopies).length === 0
  && Object.keys(entry.state.collectionRecords).length === 0
  && entry.state.formation.length === 0
  && entry.state.representativeCardId === null
  && Object.values(entry.state.supportItems).every((count) => count === 0)
)));
assert.equal(report.mapped.serials.length, 0);
assert.equal(report.mapped.memberRewardAudit.length, 0);
assert.deepEqual(report.mapped.bridgeKeys, source.bridgeKeys);

const broken = structuredClone(source);
broken.users[1].soop_id = broken.users[0].soop_id;
broken.collection.push({ user_id: 'missing-user', card_id: 'anything', count: 1 });
const brokenSnapshot = structuredClone(rankingSnapshot);
brokenSnapshot.rows[49].rank = 49;
const rejected = analyzeSeason1Export(broken, cards, {
  importedAt: 1_784_246_400_000,
  rankingSnapshot: brokenSnapshot,
});
assert.equal(rejected.ok, false);
assert.ok(rejected.issues.some((entry) => entry.code === 'DUPLICATE_SOOP_ID'));
assert.ok(rejected.issues.some((entry) => entry.code === 'ORPHAN_COLLECTION'));
assert.ok(rejected.issues.some((entry) => entry.code === 'DUPLICATE_RANK'));
assert.ok(rejected.issues.some((entry) => entry.code === 'MISSING_RANK'));

const orphanBridge = structuredClone(source);
orphanBridge.bridgeKeys.push({
  soop_id: 'missing_streamer',
  key_hash: 'f'.repeat(64),
  active: true,
});
const orphanRejected = analyzeSeason1Export(orphanBridge, cards, {
  importedAt: 1_784_246_400_000,
  rankingSnapshot,
});
assert.equal(orphanRejected.ok, false);
assert.ok(orphanRejected.issues.some((entry) => entry.code === 'ORPHAN_BRIDGE_KEY'));

console.log('renewal season1 import tests passed: 5K base, top50 rewards, unopened non-streamer exclusion');
