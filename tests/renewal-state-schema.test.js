import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  CLIENT_CACHE_FIELDS,
  GAME_STATE_SCHEMA_VERSION,
  migrateGameState,
  SERVER_AUTHORITY_FIELDS,
  validateGameState,
} from '../src/renewal/state-schema.js';
import { createDefaultState, loadState, saveState } from '../src/renewal/storage.js';

const cards = JSON.parse(fs.readFileSync(new URL('../data/renewal-cards.json', import.meta.url), 'utf8'));
const cardIds = cards.map((card) => card.id);
const now = Date.UTC(2026, 6, 17, 12, 0, 0);
const clone = (value) => JSON.parse(JSON.stringify(value));

const state = createDefaultState(now);
assert.equal(state.schemaVersion, GAME_STATE_SCHEMA_VERSION);
assert.equal(validateGameState(state, { cardIds }).valid, true);

const authority = new Set(SERVER_AUTHORITY_FIELDS);
const cache = new Set(CLIENT_CACHE_FIELDS);
assert.equal([...authority].some((field) => cache.has(field)), false, 'authority and client cache fields must be disjoint');
assert.deepEqual(new Set(Object.keys(state)), new Set([...authority, ...cache]), 'every v2 field needs an authority owner');

const legacy = clone(state);
delete legacy.schemaVersion;
delete legacy.revision;
legacy.points = 12345;
const migrated = migrateGameState(legacy);
assert.equal(migrated.ok, true);
assert.equal(migrated.migrated, true);
assert.equal(migrated.state.schemaVersion, 2);
assert.equal(migrated.state.revision, 0);
assert.equal(migrated.state.points, 12345);

const obsoleteMaterials = migrateGameState({ ...state, growthMaterials: 999 });
assert.equal(obsoleteMaterials.ok, true);
assert.equal(obsoleteMaterials.migrated, true);
assert.equal(Object.hasOwn(obsoleteMaterials.state, 'growthMaterials'), false);

const preResetItems = clone(state);
delete preResetItems.supportItems.adventureRunReset;
delete preResetItems.supportItems.quickBattleReset;
const resetItemMigration = migrateGameState(preResetItems);
assert.equal(resetItemMigration.ok, true);
assert.equal(resetItemMigration.migrated, true);
assert.equal(resetItemMigration.state.supportItems.adventureRunReset, 0);
assert.equal(resetItemMigration.state.supportItems.quickBattleReset, 0);
assert.equal(validateGameState(resetItemMigration.state, { cardIds }).valid, true);

const preMiniGameBreakdown = clone(state);
delete preMiniGameBreakdown.miniGames.pointsEarnedByGame;
preMiniGameBreakdown.miniGames.pointsEarned = 3000;
const miniGameMigration = migrateGameState(preMiniGameBreakdown);
assert.equal(miniGameMigration.migrated, true);
assert.deepEqual(miniGameMigration.state.miniGames.pointsEarnedByGame, { memory: 3000, sumTen: 0 });
assert.equal(validateGameState(miniGameMigration.state, { cardIds }).valid, true);

const legacyV1 = { ...clone(state), schemaVersion: 1, accountLevel: 432, accountExp: 987654 };
const migratedV1 = migrateGameState(legacyV1);
assert.equal(migratedV1.ok, true);
assert.equal(migratedV1.state.schemaVersion, 2);
assert.equal(Object.hasOwn(migratedV1.state, 'accountLevel'), false);
assert.equal(Object.hasOwn(migratedV1.state, 'accountExp'), false);
assert.equal(validateGameState(migratedV1.state, { cardIds }).valid, true);

assert.equal(migrateGameState({ ...state, schemaVersion: 3 }).ok, false, 'future schema versions must be rejected');

const negativePoints = clone(state);
negativePoints.points = -1;
assert.ok(validateGameState(negativePoints).issues.some(({ path }) => path === 'points'));

const duplicateFormation = clone(state);
duplicateFormation.formation[1] = duplicateFormation.formation[0];
assert.ok(validateGameState(duplicateFormation).issues.some(({ path }) => path === 'formation'));

const invalidRanking = clone(state);
invalidRanking.powerRanking.rank = 1501;
assert.ok(validateGameState(invalidRanking).issues.some(({ path }) => path === 'powerRanking.rank'));

const invalidMiniGameTotal = clone(state);
invalidMiniGameTotal.miniGames.pointsEarnedByGame.memory = 500;
assert.ok(validateGameState(invalidMiniGameTotal).issues.some(({ path }) => path === 'miniGames.pointsEarned'));

const invalidProgress = clone(state);
invalidProgress.cardProgress.bad = { enhancement: 10, exp: 0 };
const invalidProgressResult = validateGameState(invalidProgress, { cardIds });
assert.equal(invalidProgressResult.valid, false);
assert.ok(invalidProgressResult.issues.some(({ path }) => path === 'cardProgress.bad'));

const unknownField = { ...state, cheatPoints: 999999 };
assert.ok(validateGameState(unknownField).issues.some(({ path }) => path === 'cheatPoints'));

const unknownItem = clone(state);
unknownItem.supportItems.cheatBooster = 1;
assert.ok(validateGameState(unknownItem).issues.some(({ path }) => path === 'supportItems.cheatBooster'));

const storage = new Map();
globalThis.localStorage = {
  getItem: (key) => storage.get(key) ?? null,
  setItem: (key, value) => storage.set(key, value),
  removeItem: (key) => storage.delete(key),
};

const storedState = createDefaultState(now);
saveState(storedState);
assert.equal(storedState.revision, 1);
const [storageKey] = storage.keys();
assert.equal(loadState().revision, 1);

const rejectedSave = createDefaultState(now);
rejectedSave.points = -1;
assert.throws(() => saveState(rejectedSave), /Invalid game state/);
assert.equal(rejectedSave.revision, 0, 'failed saves must not advance the in-memory revision');

const storedLegacy = clone(storedState);
delete storedLegacy.schemaVersion;
delete storedLegacy.revision;
storedLegacy.points = 777;
storedLegacy.adventureAttempts = { windowStartedAt: now, count: 3 };
storage.set(storageKey, JSON.stringify(storedLegacy));
assert.equal(loadState().points, 777);
assert.equal(loadState().schemaVersion, 2);
assert.equal(Object.hasOwn(loadState(), 'adventureAttempts'), false, 'deprecated v0 fields must be discarded during migration');

storage.set(storageKey, JSON.stringify({ ...storedState, points: -500 }));
assert.equal(loadState().points, createDefaultState().points, 'corrupt local state must fall back to a safe default');

const incompleteV1 = clone(storedState);
delete incompleteV1.powerRanking;
storage.set(storageKey, JSON.stringify(incompleteV1));
assert.equal(loadState().revision, 0, 'v2 states with missing declared fields must be rejected instead of patched');

console.log('renewal state schema tests passed: v0/v1 migration, v2 validation, authority boundary, corrupt-state rejection');
