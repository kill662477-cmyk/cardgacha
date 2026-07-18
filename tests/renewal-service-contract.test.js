import assert from 'node:assert/strict';
import { createInMemoryCommandGateway } from '../src/renewal/in-memory-command-gateway.js';
import {
  GAME_COMMAND_TYPES,
  GAME_ERROR_CODES,
  createGameCommand,
  isRetryableGameError,
  validateGameCommand,
  validateGameResponse,
} from '../src/renewal/service-contract.js';

const clock = { now: () => 1_721_200_000_000 };
const rng = { next: () => 0.25 };
const initialSnapshot = { schemaVersion: 1, revision: 4, points: 1_000, formation: ['a'] };
const handlers = {
  [GAME_COMMAND_TYPES.PURCHASE_PACK]: ({ snapshot }) => ({
    snapshot: { ...snapshot, points: snapshot.points - 50 },
    result: { cards: ['card-a', 'card-b', 'card-c'], spentPoints: 50 },
  }),
  [GAME_COMMAND_TYPES.UPDATE_FORMATION]: ({ command, snapshot }) => ({
    snapshot: { ...snapshot, formation: command.payload.formation },
    result: { formation: command.payload.formation },
  }),
};

const gateway = createInMemoryCommandGateway({ initialSnapshot, handlers, clock, rng });
const purchase = createGameCommand({
  type: GAME_COMMAND_TYPES.PURCHASE_PACK,
  payload: { productId: 'general', quantity: 1, race: null },
  expectedRevision: 4,
  idempotencyKey: 'purchase-00000001',
  clientSentAt: clock.now(),
});

const first = await gateway.execute(purchase);
assert.equal(first.ok, true);
assert.equal(first.revision, 5);
assert.equal(first.snapshot.points, 950);
assert.equal(first.serverSeed, 0x40000000);
assert.equal(validateGameResponse(first).valid, true);
assert.equal(gateway.getProcessedCount(), 1);

const replay = await gateway.execute(purchase);
assert.deepEqual(replay, first, 'same idempotency key must return the original response');
assert.equal(gateway.getSnapshot().points, 950, 'replay must not spend points twice');
assert.equal(gateway.getProcessedCount(), 1);

const conflictingKeyUse = { ...purchase, payload: { ...purchase.payload, quantity: 10 } };
const reused = await gateway.execute(conflictingKeyUse);
assert.equal(reused.ok, false);
assert.equal(reused.code, GAME_ERROR_CODES.IDEMPOTENCY_KEY_REUSED);
assert.equal(gateway.getSnapshot().points, 950);

const stale = createGameCommand({
  type: GAME_COMMAND_TYPES.UPDATE_FORMATION,
  payload: { formation: ['b'] },
  expectedRevision: 4,
  idempotencyKey: 'formation-00000001',
  clientSentAt: clock.now(),
});
const conflict = await gateway.execute(stale);
assert.equal(conflict.ok, false);
assert.equal(conflict.code, GAME_ERROR_CODES.VERSION_CONFLICT);
assert.equal(conflict.revision, 5);
assert.equal(conflict.latestSnapshot.points, 950);
assert.equal(conflict.retryable, false);
assert.equal(validateGameResponse(conflict).valid, true);

const current = createGameCommand({ ...stale, expectedRevision: 5, idempotencyKey: 'formation-00000002' });
const updated = await gateway.execute(current);
assert.equal(updated.ok, true);
assert.deepEqual(updated.snapshot.formation, ['b']);
assert.equal(updated.revision, 6);

const invalid = validateGameCommand({ ...purchase, commandId: 'mismatch' });
assert.equal(invalid.valid, false);
assert.ok(invalid.issues.some((entry) => entry.path === 'idempotencyKey'));

const minigameStart = createGameCommand({
  type: GAME_COMMAND_TYPES.START_MINIGAME,
  payload: { game: 'memory', difficulty: 'advanced' },
  expectedRevision: 6,
  idempotencyKey: 'minigame-start-0001',
  clientSentAt: clock.now(),
});
assert.equal(validateGameCommand(minigameStart).valid, true);
const minigameFinish = createGameCommand({
  type: GAME_COMMAND_TYPES.FINISH_MINIGAME,
  payload: { runId: 'run-00000001', inputLog: [{ index: 2, atMs: 120 }], score: 0 },
  expectedRevision: 7,
  idempotencyKey: 'minigame-finish-001',
  clientSentAt: clock.now(),
});
assert.equal(validateGameCommand(minigameFinish).valid, true);
assert.equal(validateGameCommand({
  ...minigameFinish,
  payload: { ...minigameFinish.payload, inputDigest: 'client-forged' },
}).valid, false, 'client-computed minigame digest must be rejected');
assert.equal(validateGameCommand({
  ...minigameStart,
  payload: { ...minigameStart.payload, verifiedScore: 99999 },
}).valid, false, 'server verdict fields must be rejected');

const worldBossAttack = createGameCommand({
  type: GAME_COMMAND_TYPES.ATTACK_WORLD_BOSS,
  payload: { eventId: 'noise-zero-20260718-17' },
  expectedRevision: 7,
  idempotencyKey: 'worldboss-attack-001',
  clientSentAt: clock.now(),
});
assert.equal(validateGameCommand(worldBossAttack).valid, true);
assert.equal(validateGameCommand({
  ...worldBossAttack,
  payload: { ...worldBossAttack.payload, damage: 999999999 },
}).valid, false, 'client-computed world-boss damage must be rejected');
const worldBossClaim = createGameCommand({
  type: GAME_COMMAND_TYPES.CLAIM_WORLD_BOSS_REWARD,
  payload: { eventId: 'noise-zero-20260718-17' },
  expectedRevision: 8,
  idempotencyKey: 'worldboss-claim-001',
  clientSentAt: clock.now(),
});
assert.equal(validateGameCommand(worldBossClaim).valid, true);
assert.equal(validateGameCommand({
  ...worldBossClaim,
  payload: { ...worldBossClaim.payload, tier: 5 },
}).valid, false, 'client-selected reward tier must be rejected');

assert.equal(isRetryableGameError({ ok: false, retryable: true, code: GAME_ERROR_CODES.OFFLINE }), true);
assert.equal(isRetryableGameError(conflict), false);
assert.equal(validateGameResponse({ ...first, snapshot: { ...first.snapshot, revision: 999 } }).valid, false);

console.log('renewal service contract tests passed: validation, idempotency replay, revision conflict, server seed');
