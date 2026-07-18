import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../supabase/renewal_migration_001_accounts_reset.sql', import.meta.url), 'utf8');
const normalized = sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();

for (const sourceTable of [
  'gacha_users',
  'gacha_collection',
  'gacha_season1_final_top50',
  'gacha_soop_bridge_keys',
]) {
  const mutation = new RegExp(`(?:update|delete\\s+from|truncate(?:\\s+table)?|drop\\s+table)\\s+(?:public\\.)?${sourceTable}\\b`, 'i');
  assert.equal(mutation.test(normalized), false, `season1 source mutation found: ${sourceTable}`);
}

assert.match(normalized, /create table if not exists public\.gacha_s2_accounts/);
assert.match(normalized, /create table if not exists public\.gacha_s2_streamer_bridges/);
assert.match(normalized, /create table if not exists public\.gacha_s2_player_states/);
assert.match(normalized, /create table if not exists public\.gacha_s2_player_cards/);
assert.match(normalized, /is_streamer boolean not null default false/);
assert.match(normalized, /key_hash text not null unique check/);
assert.match(normalized, /sourcebridgekeyrows/);
assert.match(normalized, /retainedbridgekeyrows/);
assert.match(normalized, /orphanbridgekeyrows/);
assert.match(normalized, /insert into public\.gacha_s2_streamer_bridges/);
assert.match(normalized, /select a\.id, b\.soop_id, b\.key_hash, b\.active, b\.created_at, b\.last_used_at/);
assert.match(normalized, /where coalesce\(c\.total_cards, 0\) > 0 or exists \( select 1 from public\.gacha_soop_bridge_keys/);
assert.match(normalized, /select a\.id, 5000 \+ a\.season1_rank_reward_points/);
assert.match(normalized, /when p_rank between 1 and 10 then 30000/);
assert.match(normalized, /when p_rank between 41 and 50 then 5000/);
assert.match(normalized, /distinctrankingusers/);
assert.match(normalized, /rankingusersexcludednocards/);
assert.match(normalized, /rankbonustotal'\)::bigint <> 800000/);
assert.match(normalized, /2026-07-18t01:14:01\.623z/);
assert.doesNotMatch(normalized, /insert into public\.gacha_s2_player_cards/);
assert.match(normalized, /if exists \(select 1 from public\.gacha_s2_player_cards\)/);
assert.match(normalized, /alter table public\.gacha_s2_accounts enable row level security/);
assert.match(normalized, /alter table public\.gacha_s2_streamer_bridges enable row level security/);
assert.match(normalized, /revoke all on table public\.gacha_s2_accounts from public, anon, authenticated/);
assert.match(normalized, /revoke all on table public\.gacha_s2_streamer_bridges from public, anon, authenticated/);
assert.match(normalized, /grant execute on function public\.gacha_s2_import_season1_accounts\(uuid, integer, integer\) to service_role/);

console.log('renewal database migration tests passed: read-only source, account and bridge carryover, clean game state');
