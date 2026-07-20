import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { GAME_COMMAND_TYPES, createGameCommand } from '../src/renewal/service-contract.js';
import { createServerCommandRouter } from '../src/renewal/server-command-router.js';
import { DISMANTLE_RULES } from '../src/renewal/config.js';
import fs from 'node:fs';

const cards = JSON.parse(fs.readFileSync(new URL('../data/renewal-cards.json', import.meta.url), 'utf8'));

// 1. Edge Router Parameter Mapping Test
const basePayload = createGameCommand({
  type: GAME_COMMAND_TYPES.DISMANTLE_CARDS,
  expectedRevision: 10,
  payload: { rarity: 'B' },
  idempotencyKey: 'test-dismantle-key',
  clientSentAt: 10000,
});

let lastCall = null;
const gateway = {
  activeBalanceVersion: async () => 'test-version',
  rpc: async (name, args) => {
    lastCall = { name, args };
    return { ok: true };
  }
};

const router = createServerCommandRouter({ gateway, cards, clock: { now: () => 10000 } });
await router.execute('u-1', basePayload);

assert.equal(lastCall.name, 'gacha_s2_dismantle_cards');
assert.equal(lastCall.args.p_rarity, 'B');

// 2. Migration SQL Static Analysis
const sql = await readFile(new URL('../supabase/renewal_migration_023_dismantle.sql', import.meta.url), 'utf8');
const normalized = sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();

assert.match(normalized, /create or replace function public\.gacha_s2_dismantle_cards/);
assert.match(normalized, /p_user_id uuid/);
assert.match(normalized, /p_expected_revision bigint/);
assert.match(normalized, /p_idempotency_key text/);
assert.match(normalized, /p_rarity text/);

// Ensure it checks revision conflicts
assert.match(normalized, /if p_expected_revision <> v_revision then/);
assert.match(normalized, /'version_conflict'/);

// Ensure it locks the account row
assert.match(normalized, /from public\.gacha_s2_player_states where user_id = p_user_id for update/);

// Ensure it checks the rarity rule
assert.match(normalized, /v_config->'dismantlerules'->'droprates'->p_rarity/);

// Ensure it inserts audit log
assert.match(normalized, /insert into public\.gacha_s2_command_audit/);

// 3. Dismantle Rules Config Test
assert.ok(DISMANTLE_RULES.dropRates['SSS']);
assert.equal(DISMANTLE_RULES.dropRates['SSS'].potionRate, 0.90);
assert.equal(DISMANTLE_RULES.dropRates['F'].points, 5);

console.log('renewal dismantle tests passed: edge router mapping, sql RPC logic, config definitions');
