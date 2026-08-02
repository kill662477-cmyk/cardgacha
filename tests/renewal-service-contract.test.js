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
const hardQuickBattle = createGameCommand({
  type: GAME_COMMAND_TYPES.CLAIM_QUICK_BATTLE,
  payload: { mode: 'hard' },
  expectedRevision: 6,
  idempotencyKey: 'hard-quick-contract-1',
  clientSentAt: clock.now(),
});
assert.equal(validateGameCommand(hardQuickBattle).valid, true);
assert.equal(
  validateGameCommand({ ...hardQuickBattle, payload: { mode: 'hell' } }).valid,
  false,
  'HELL quick battle must be rejected by the shared client/edge contract',
);
assert.equal(validateGameCommand({ ...hardQuickBattle, payload: { mode: 'nightmare' } }).valid, false);
const hellAdventure = createGameCommand({
  type: GAME_COMMAND_TYPES.START_ADVENTURE_RUN,
  payload: { mode: 'hell' },
  expectedRevision: 6,
  idempotencyKey: 'hell-start-contract-1',
  clientSentAt: clock.now(),
});
assert.equal(validateGameCommand(hellAdventure).valid, true);
const minigameFinish = createGameCommand({
  type: GAME_COMMAND_TYPES.FINISH_MINIGAME,
  payload: { runId: 'run-00000001', inputLog: [{ start: 2, end: 3, atMs: 120 }], score: 0 },
  expectedRevision: 7,
  idempotencyKey: 'minigame-finish-001',
  clientSentAt: clock.now(),
});
assert.equal(validateGameCommand(minigameFinish).valid, true);
const ladderPlay = createGameCommand({
  type: GAME_COMMAND_TYPES.PLAY_LADDER,
  payload: { lane: 5 },
  expectedRevision: 8,
  idempotencyKey: 'ladder-play-00001',
  clientSentAt: clock.now(),
});
assert.equal(validateGameCommand(ladderPlay).valid, true);
assert.equal(validateGameCommand({ ...ladderPlay, payload: { lane: 6 } }).valid, false);
const lottoPurchase = createGameCommand({
  type: GAME_COMMAND_TYPES.BUY_LOTTO_TICKET,
  payload: { numbers: [1, 4, 7, 10, 13, 18] },
  expectedRevision: 8,
  idempotencyKey: 'lotto-buy-000001',
  clientSentAt: clock.now(),
});
assert.equal(validateGameCommand(lottoPurchase).valid, true);
assert.equal(validateGameCommand({
  ...lottoPurchase,
  payload: { numbers: [1, 1, 7, 10, 13, 18] },
}).valid, false, '로또 한 티켓 안에서 번호를 중복 선택할 수 없어야 한다');
assert.equal(validateGameCommand({
  ...lottoPurchase,
  payload: { numbers: [1, 4, 7, 10, 13, 19] },
}).valid, false, '로또 번호는 1~18만 허용해야 한다');
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

for (const supportCommand of [
  createGameCommand({ type: GAME_COMMAND_TYPES.PURCHASE_SUPPORT_PACK, payload: { quantity: 10 }, expectedRevision: 8, idempotencyKey: 'support-pack-00001', clientSentAt: clock.now() }),
  createGameCommand({ type: GAME_COMMAND_TYPES.USE_SUPPORT_ITEM, payload: { itemId: 'cardExpPotion', targetCardId: 'card-a', race: null }, expectedRevision: 8, idempotencyKey: 'support-use-000001', clientSentAt: clock.now() }),
  createGameCommand({ type: GAME_COMMAND_TYPES.USE_SUPPORT_ITEM, payload: { itemId: 'traitReroll', targetCardId: 'card-a', race: null }, expectedRevision: 8, idempotencyKey: 'trait-reroll-00001', clientSentAt: clock.now() }),
  createGameCommand({ type: GAME_COMMAND_TYPES.SET_REPRESENTATIVE_CARD, payload: { cardId: 'card-a' }, expectedRevision: 8, idempotencyKey: 'representative-0001', clientSentAt: clock.now() }),
  createGameCommand({ type: GAME_COMMAND_TYPES.SET_CARD_LOCK, payload: { cardId: 'card-a', locked: true }, expectedRevision: 8, idempotencyKey: 'card-lock-0000001', clientSentAt: clock.now() }),
]) assert.equal(validateGameCommand(supportCommand).valid, true);

const cardSelector = createGameCommand({
  type: GAME_COMMAND_TYPES.REDEEM_CARD_SELECTOR,
  payload: { itemId: 'sssCardSelector', cardId: 'jidudu-1' },
  expectedRevision: 8,
  idempotencyKey: 'card-selector-0001',
  clientSentAt: clock.now(),
});
assert.equal(validateGameCommand(cardSelector).valid, true);
assert.equal(validateGameCommand({
  ...cardSelector,
  payload: { itemId: 'premiumTicket', cardId: 'jidudu-1' },
}).valid, false);

assert.equal(isRetryableGameError({ ok: false, retryable: true, code: GAME_ERROR_CODES.OFFLINE }), true);
assert.equal(isRetryableGameError(conflict), false);
assert.equal(validateGameResponse({ ...first, snapshot: { ...first.snapshot, revision: 999 } }).valid, false);

console.log('renewal service contract tests passed: validation, idempotency replay, revision conflict, server seed');
