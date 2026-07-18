import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../supabase/renewal_migration_003_command_foundation.sql', import.meta.url), 'utf8');
const normalized = sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();

assert.match(normalized, /create table if not exists public\.gacha_s2_collection_records/);
assert.match(normalized, /primary key \(user_id, card_id\)/);
assert.match(normalized, /card_id text not null references public\.gacha_s2_card_catalog\(card_id\)/);
assert.match(normalized, /create table if not exists public\.gacha_s2_command_audit/);
assert.match(normalized, /committed_revision bigint not null check \(committed_revision = expected_revision \+ 1\)/);
assert.match(normalized, /unique \(user_id, command_id\)/);
assert.match(normalized, /create or replace function public\.gacha_s2_get_player_snapshot\(p_user_id uuid\)/);
assert.match(normalized, /'collectionrecords', coalesce/);
assert.match(normalized, /'cardcopies', coalesce/);
assert.match(normalized, /create or replace function public\.gacha_s2_update_formation/);
assert.match(normalized, /for update/);
assert.match(normalized, /encode\(digest\(jsonb_build_object/);
assert.doesNotMatch(normalized, /p_request_hash/);
assert.match(normalized, /cardinality\(p_formation\) < 1 or cardinality\(p_formation\) > 5/);
assert.match(normalized, /count\(distinct card_id\).*<> cardinality\(p_formation\)/);
assert.match(normalized, /owned\.copies > 0 and catalog\.rarity <> 'ex'/);
assert.match(normalized, /set formation = p_formation, revision = revision \+ 1/);
assert.match(normalized, /now\(\) \+ interval '24 hours'/);
assert.match(normalized, /insert into public\.gacha_s2_command_audit/);
assert.match(normalized, /'serverseed', 0/);

const replayCheck = normalized.indexOf('select * into v_previous from public.gacha_s2_idempotency');
const revisionCheck = normalized.indexOf('if p_expected_revision <> v_revision then');
const stateMutation = normalized.indexOf('update public.gacha_s2_player_states set formation');
const idempotencyWrite = normalized.indexOf('insert into public.gacha_s2_idempotency');
assert.ok(replayCheck >= 0 && replayCheck < revisionCheck, 'idempotency replay must precede revision conflict');
assert.ok(revisionCheck < stateMutation && stateMutation < idempotencyWrite, 'validate before atomic state and response commit');

for (const table of ['gacha_s2_collection_records', 'gacha_s2_command_audit']) {
  assert.match(normalized, new RegExp(`alter table public\\.${table} enable row level security`));
  assert.match(normalized, new RegExp(`revoke all on table public\\.${table} from public, anon, authenticated`));
}
assert.match(normalized, /revoke all on function public\.gacha_s2_update_formation\(uuid, bigint, text, text\[\]\) from public, anon, authenticated/);
assert.match(normalized, /grant execute on function public\.gacha_s2_update_formation\(uuid, bigint, text, text\[\]\) to service_role/);
assert.doesNotMatch(normalized, /grant execute on function public\.gacha_s2_update_formation.*to (?:anon|authenticated)/);

console.log('renewal command foundation tests passed: snapshot, replay, revision lock, owned combat formation');
