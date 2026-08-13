import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import cards from '../data/renewal-cards.json' with { type: 'json' };
import { BALANCE_VERSION } from '../src/renewal/config.js';
import {
  buildGuildApplicantProfile,
  createServerCommandRouter,
} from '../src/renewal/server-command-router.js';
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

const applicantProfile = buildGuildApplicantProfile({
  userId: 'applicant',
  nickname: '신청자',
  powerSnapshot: 1,
  formation: playable.map((card, index) => ({
    cardId: card.id,
    enhancement: 3,
    race: index === 0 ? ['저그', '테란', '프로토스'].find((race) => race !== card.race) : card.race,
  })),
  registeredCardIds: playable.map((card) => card.id),
  guildBuff: { atk: 0, hp: 0, def: 0 },
}, cards);
assert.equal(applicantProfile.power > 1, true, '신청자 전투력은 현재 덱·강화·도감으로 계산해야 한다');
assert.equal(applicantProfile.formation.length, 5);
assert.notEqual(applicantProfile.formation[0].race, playable[0].race, '길드 덱 조회는 계정 종족 변경값을 표시해야 한다');
assert.equal('registeredCardIds' in applicantProfile, false, '도감 원본은 승인자 브라우저에 노출하지 않는다');
assert.equal('guildBuff' in applicantProfile, false, '내부 전투력 계산값은 승인자 브라우저에 노출하지 않는다');

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
assert.equal(adventure.args.p_mode, 'normal');
assert.match(adventure.args.p_verification_digest, /^[0-9a-f]{64}$/);
assert.equal(calls.some(({ name }) => name === 'gacha_s2_get_player_snapshot'), true);

const lockedHard = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.START_ADVENTURE_RUN,
  { mode: 'hard' },
  'hard-locked-edge-001',
));
assert.equal(lockedHard.code, 'COMMAND_REJECTED');
snapshot.clearedStage = 50;
const hardQuick = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.CLAIM_QUICK_BATTLE,
  { mode: 'hard' },
  'hard-quick-edge-0001',
));
assert.equal(hardQuick.rpc, 'gacha_s2_claim_quick_battle');
assert.equal(hardQuick.args.p_mode, 'hard');
const hellQuickCommand = command(
  GAME_COMMAND_TYPES.CLAIM_QUICK_BATTLE,
  { mode: 'hard' },
  'hell-quick-edge-0001',
);
hellQuickCommand.payload.mode = 'hell';
const hellQuick = await router.execute('user-fixed-by-auth', hellQuickCommand);
assert.equal(hellQuick.code, 'VALIDATION_FAILED', 'edge router must reject HELL quick battle before any RPC');
snapshot.clearedStage = 0;

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

const advancedSupportPack = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.PURCHASE_ADVANCED_SUPPORT_PACK,
  { quantity: 10 },
  'advanced-pack-0001',
));
assert.equal(advancedSupportPack.rpc, 'gacha_s2_purchase_advanced_support_pack');

const fixedSupportItem = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.PURCHASE_FIXED_SUPPORT_ITEM,
  { itemId: 'raceChangeSelector', targetCardId: 'jidudu-1', race: '프로토스' },
  'fixed-item-buy-001',
));
assert.equal(fixedSupportItem.rpc, 'gacha_s2_purchase_fixed_support_item');
assert.equal(fixedSupportItem.args.p_item_id, 'raceChangeSelector');
assert.equal(fixedSupportItem.args.p_target_card_id, 'jidudu-1');
assert.equal(fixedSupportItem.args.p_race, '프로토스');

const cardSelector = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.REDEEM_CARD_SELECTOR,
  { itemId: 'sssCardSelector', cardId: 'jidudu-1' },
  'card-selector-0001',
));
assert.equal(cardSelector.rpc, 'gacha_s2_redeem_card_selector');
assert.equal(cardSelector.args.p_item_id, 'sssCardSelector');
assert.equal(cardSelector.args.p_card_id, 'jidudu-1');

const cardLock = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.SET_CARD_LOCK,
  { cardId: playable[0].id, locked: true },
  'card-lock-0000001',
));
assert.equal(cardLock.rpc, 'gacha_s2_set_card_lock');

const ladder = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.PLAY_LADDER,
  { lane: 4 },
  'ladder-edge-00001',
));
assert.equal(ladder.rpc, 'gacha_s2_play_ladder');
assert.equal(ladder.args.p_lane, 4);
assert.equal(ladder.args.p_user_id, 'user-fixed-by-auth');

const lotto = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.BUY_LOTTO_TICKET,
  { numbers: [1, 4, 7, 10, 13, 18] },
  'lotto-edge-00001',
));
assert.equal(lotto.rpc, 'gacha_s2_buy_lotto_ticket');
assert.deepEqual(lotto.args.p_numbers, [1, 4, 7, 10, 13, 18]);
assert.equal(lotto.args.p_user_id, 'user-fixed-by-auth');

const market = await router.execute('user-fixed-by-auth', command(
  GAME_COMMAND_TYPES.MARKET_TRADE,
  { symbol: 'TMT', side: 'buy', quantity: 3, positionType: 'inverse', multiplier: 4 },
  'market-edge-00001',
));
assert.equal(market.rpc, 'gacha_s2_market_trade');
assert.equal(market.args.p_symbol, 'TMT');
assert.equal(market.args.p_position_type, 'inverse');
assert.equal(market.args.p_multiplier, 4);
assert.equal(market.args.p_side, 'buy');
assert.equal(market.args.p_quantity, 3);
assert.equal(market.args.p_user_id, 'user-fixed-by-auth');

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
assert.equal(mismatch.code, 'VERSION_CONFLICT');
assert.equal(mismatch.details, null, 'internal verification details must not reach the browser');

const edgeSource = await readFile(new URL('../supabase/functions/game-command/index.ts', import.meta.url), 'utf8');
const edgeConfig = await readFile(new URL('../supabase/config.toml', import.meta.url), 'utf8');
const failureAudit = await readFile(
  new URL('../supabase/migrations/20260726110000_command_failure_audit.sql', import.meta.url),
  'utf8',
);
assert.match(edgeSource, /supabaseAdmin\.auth\.getUser\(jwt\)/);
assert.match(edgeSource, /p_auth_user_id: user\.id/);
assert.match(edgeSource, /supabaseAdmin\.rpc/);
assert.match(edgeSource, /gacha_s2_resolve_auth_account/);
assert.match(edgeSource, /const userId = String\(accountId\)/);
assert.doesNotMatch(edgeSource, /body\.userId|body\.user_id/);
assert.match(edgeSource, /GAME_ALLOWED_ORIGINS/);
assert.match(edgeSource, /GAME_MAINTENANCE_MODE/);
assert.match(edgeSource, /code: 'MAINTENANCE'/);
assert.match(edgeSource, /\}, 503\)/);
assert.match(edgeSource, /MAX_BODY_BYTES/);
assert.match(edgeSource, /body\.kind === 'powerRanking'/);
assert.match(edgeSource, /body\.kind === 'bridgeStatus'/);
assert.match(edgeSource, /body\.kind === 'lottoState'/);
assert.match(edgeSource, /gacha_s2_get_lotto_state_v2/);
assert.doesNotMatch(edgeSource, /body\.kind === 'lottoHistory'/);
assert.match(edgeSource, /body\.kind === 'mailbox'/);
assert.match(edgeSource, /gacha_s2_get_mailbox/);
assert.match(edgeSource, /body\.kind === 'mailboxRead'/);
assert.match(edgeSource, /gacha_s2_mark_mail_read/);
assert.match(edgeSource, /UUID_PATTERN\.test\(body\.mailId\)/);
assert.match(edgeSource, /req\.body\.getReader\(\)/);
assert.match(edgeSource, /X-Request-ID/);
assert.match(edgeSource, /gacha_s2_command_failures/);
assert.match(edgeSource, /shouldPersistCommandFailure\(result\.code\)/);
assert.match(edgeConfig, /\[functions\.game-command\]\s+verify_jwt = false/);
assert.match(failureAudit, /create table if not exists public\.gacha_s2_command_failures/);
assert.match(failureAudit, /unique \(request_id\)/);
assert.match(failureAudit, /enable row level security/);
assert.doesNotMatch(failureAudit, /^\s*(payload|authorization|jwt)\s+/im);

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
