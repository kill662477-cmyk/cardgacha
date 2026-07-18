import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import cards from '../data/renewal-cards.json' with { type: 'json' };
import { BALANCE_VERSION } from '../src/renewal/config.js';
import { createServerCommandRouter } from '../src/renewal/server-command-router.js';
import { GAME_COMMAND_TYPES, createGameCommand } from '../src/renewal/service-contract.js';

const playable = cards.filter((card) => card.rarity !== 'EX').slice(0, 5);
const snapshot = {
  revision: 4,
  formation: playable.map((card) => card.id),
  cardCopies: Object.fromEntries(playable.map((card) => [card.id, 1])),
  cardProgress: Object.fromEntries(playable.map((card) => [card.id, { enhancement: 3, exp: 0 }])),
  collectionRecords: {},
  worldBoss: { attempts: 0 },
};
const calls = [];
const gateway = {
  activeBalanceVersion: async () => BALANCE_VERSION,
  rpc: async (name, args) => {
    calls.push({ name, args });
    if (name === 'gacha_s2_get_player_snapshot') return snapshot;
    if (name === 'gacha_s2_get_world_boss_status') return { player: { attempts: 1 } };
    return { ok: true, rpc: name, args };
  },
};
const router = createServerCommandRouter({ gateway, cards, clock: { now: () => 1234 } });
const command = (type, payload, id) => createGameCommand({
  type,
  payload,
  expectedRevision: 4,
  idempotencyKey: id,
  clientSentAt: 1000,
});

const powerRanking = await router.getPowerRanking('user-fixed-by-auth');
assert.equal(powerRanking.rpc, 'gacha_s2_get_power_ranking');
assert.equal(powerRanking.args.p_user_id, 'user-fixed-by-auth');
assert.equal(Number.isInteger(powerRanking.args.p_verified_power), true);
assert.equal(powerRanking.args.p_verified_power > 0, true);

const formation = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.UPDATE_FORMATION,
  { formation: playable.map((card) => card.id) },
  'formation-edge-001',
));
assert.equal(formation.rpc, 'gacha_s2_update_formation');
assert.equal(formation.args.p_user_id, 'user-fixed-by-auth');
assert.equal(formation.args.p_expected_revision, 4);

calls.length = 0;
const adventure = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.START_ADVENTURE_RUN,
  {},
  'adventure-edge-001',
));
assert.equal(adventure.rpc, 'gacha_s2_start_adventure_run');
assert.equal(Number.isInteger(adventure.args.p_verified_cleared_stages), true);
assert.match(adventure.args.p_verification_digest, /^[0-9a-f]{64}$/);
assert.equal(calls.some(({ name }) => name === 'gacha_s2_get_player_snapshot'), true);

calls.length = 0;
const worldBoss = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.ATTACK_WORLD_BOSS,
  { eventId: 'noise-zero-20260718-17' },
  'worldboss-edge-001',
));
assert.equal(worldBoss.rpc, 'gacha_s2_attack_world_boss');
assert.equal(worldBoss.args.p_user_id, 'user-fixed-by-auth');
assert.equal(worldBoss.args.p_verified_damage > 0, true);
assert.match(worldBoss.args.p_verification_digest, /^[0-9a-f]{64}$/);

const idle = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.CLAIM_ADVENTURE_REWARDS,
  { mode: 'offline' },
  'idle-edge-0000001',
));
assert.equal(idle.rpc, 'gacha_s2_claim_idle_reward');
assert.equal(typeof idle.args.p_idle_bonus, 'number');

const supportPack = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.PURCHASE_SUPPORT_PACK,
  { quantity: 10 },
  'support-pack-00001',
));
assert.equal(supportPack.rpc, 'gacha_s2_purchase_support_pack');

const cardLock = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.SET_CARD_LOCK,
  { cardId: playable[0].id, locked: true },
  'card-lock-0000001',
));
assert.equal(cardLock.rpc, 'gacha_s2_set_card_lock');

const mismatchRouter = createServerCommandRouter({
  gateway: { ...gateway, activeBalanceVersion: async () => 'stale-balance' },
  cards,
  clock: { now: () => 1234 },
});
const mismatch = await mismatchRouter.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.START_ADVENTURE_RUN,
  {},
  'mismatch-edge-001',
));
assert.equal(mismatch.code, 'INTERNAL_ERROR');
assert.equal(mismatch.details, null, 'internal verification details must not reach the browser');

const edgeSource = await readFile(new URL('../supabase/functions/game-command/index.ts', import.meta.url), 'utf8');
const edgeConfig = await readFile(new URL('../supabase/config.toml', import.meta.url), 'utf8');
assert.match(edgeSource, /createSupabaseContext\(req, \{ auth: 'user' \}\)/);
assert.match(edgeSource, /context\.userClaims\.id/);
assert.match(edgeSource, /context\.supabaseAdmin(?: as any)?\)\.rpc/);
assert.match(edgeSource, /gacha_s2_resolve_auth_account/);
assert.match(edgeSource, /const userId = String\(accountId\)/);
assert.doesNotMatch(edgeSource, /body\.userId|body\.user_id|SUPABASE_SERVICE_ROLE_KEY/);
assert.match(edgeSource, /GAME_ALLOWED_ORIGINS/);
assert.match(edgeSource, /MAX_BODY_BYTES/);
assert.match(edgeSource, /body\.kind === 'powerRanking'/);
assert.match(edgeSource, /body\.kind === 'bridgeStatus'/);
assert.match(edgeSource, /req\.body\.getReader\(\)/);
assert.match(edgeConfig, /\[functions\.game-command\]\s+verify_jwt = false/);

const generatedPairs = [
  ['src/renewal/config.js', 'supabase/functions/_shared/generated/config.js'],
  ['src/renewal/battle.js', 'supabase/functions/_shared/generated/battle.js'],
  ['src/renewal/collection.js', 'supabase/functions/_shared/generated/collection.js'],
  ['src/renewal/worldboss-schedule.js', 'supabase/functions/_shared/generated/worldboss-schedule.js'],
  ['src/renewal/worldboss.js', 'supabase/functions/_shared/generated/worldboss.js'],
  ['src/renewal/service-contract.js', 'supabase/functions/_shared/generated/service-contract.js'],
  ['src/renewal/server-command-router.js', 'supabase/functions/_shared/generated/server-command-router.js'],
  ['data/renewal-cards.json', 'supabase/functions/_shared/generated/cards.json'],
];
for (const [source, generated] of generatedPairs) {
  assert.equal(
    await readFile(new URL(`../${source}`, import.meta.url), 'utf8'),
    await readFile(new URL(`../${generated}`, import.meta.url), 'utf8'),
    `stale Edge shared module: ${generated}`,
  );
}

console.log('renewal Edge router tests passed: auth identity, RPC mapping, trusted battle verdicts, shared sync');
