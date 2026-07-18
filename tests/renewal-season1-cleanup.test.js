import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../supabase/renewal_migration_999_drop_season1.sql', import.meta.url), 'utf8');
const normalized = sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();

assert.match(normalized, /current_setting\('app\.gacha_s2_api_cutover', true\).*season2_api_only/);
assert.match(normalized, /current_setting\('app\.gacha_s2_confirm_drop', true\).*drop_season1_after_verified_backup/);
assert.match(normalized, /from public\.gacha_s2_import_batches order by imported_at desc limit 1/);
assert.match(normalized, /v_source_users <> v_batch\.source_users/);
assert.match(normalized, /v_s2_accounts <> v_batch\.retained_users/);
assert.match(normalized, /v_source_bridges <> v_s2_bridges/);
assert.match(normalized, /new_bridge\.key_hash = old_bridge\.key_hash/);
assert.doesNotMatch(normalized, /\bcascade\b/);

const expectedTables = new Set([
  'gacha_prediction_votes',
  'gacha_prediction_events',
  'gacha_soop_donation_events',
  'gacha_soop_bridge_keys',
  'gacha_card_serials',
  'gacha_card_counters',
  'gacha_member_rewards',
  'gacha_announcements',
  'gacha_collection',
  'gacha_rate_limits',
  'gacha_season1_final_top50',
  'gacha_users',
]);
const droppedTables = new Set([...normalized.matchAll(/drop table if exists public\.([a-z0-9_]+)/g)].map((match) => match[1]));
assert.deepEqual(droppedTables, expectedTables);
assert.ok([...droppedTables].every((name) => !name.startsWith('gacha_s2_')));

console.log('renewal Season 1 cleanup tests passed: guarded, allowlisted, no cascade');
