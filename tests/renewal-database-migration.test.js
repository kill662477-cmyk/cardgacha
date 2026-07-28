import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../supabase/renewal_migration_001_accounts_reset.sql', import.meta.url), 'utf8');
const normalized = sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const globalRewardSql = await readFile(
  new URL('../supabase/migrations/20260723000076_ss_sss_buff_new_ss_cards_global_reward_50k.sql', import.meta.url),
  'utf8',
);
const indexHtml = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const mailboxSql = await readFile(
  new URL('../supabase/migrations/20260727203000_personal_mailbox.sql', import.meta.url),
  'utf8',
);
const soopEventRewardSql = await readFile(
  new URL('../supabase/migrations/20260727231500_soop_post_202512799_reward_batch_1.sql', import.meta.url),
  'utf8',
);
const soopEventBatch4Sql = await readFile(
  new URL('../supabase/migrations/20260728232000_soop_post_202512799_reward_batch_4.sql', import.meta.url),
  'utf8',
);

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

assert.match(globalRewardSql, /lock table public\.gacha_s2_player_states in share row exclusive mode/);
assert.match(globalRewardSql, /points_granted integer not null default 50000/);
assert.match(globalRewardSql, /set points = state\.points \+ reward\.points_granted/);
assert.match(globalRewardSql, /and reward\.points_after is null/);
assert.match(globalRewardSql, /v_reward_total <> v_reward_count::bigint \* 50000/);
assert.match(globalRewardSql, /revoke all on table public\.gacha_s2_ss_sss_buff_reward_20260723/);
assert.match(indexHtml, /id="mailboxList"/);
assert.match(indexHtml, /id="mailboxStatus"/);
assert.match(indexHtml, /id="mailCloseButton"[^>]+type="submit"/);
assert.doesNotMatch(indexHtml, /mail_kammon_victory_100k_20260727_read/);
assert.match(mailboxSql, /create table if not exists public\.gacha_s2_mailbox/);
assert.match(mailboxSql, /unique \(user_id, event_key\)/);
assert.match(mailboxSql, /create or replace function public\.gacha_s2_deliver_mail/);
assert.match(mailboxSql, /create or replace function public\.gacha_s2_get_mailbox/);
assert.match(mailboxSql, /create or replace function public\.gacha_s2_mark_mail_read/);
assert.match(mailboxSql, /where user_id = p_user_id and id = p_mail_id/);
assert.match(mailboxSql, /enable row level security/);
assert.match(mailboxSql, /revoke all on table public\.gacha_s2_mailbox from public, anon, authenticated/);
assert.match(soopEventRewardSql, /lock table public\.gacha_s2_player_states in share row exclusive mode/);
assert.match(soopEventRewardSql, /create table if not exists public\.gacha_s2_soop_post_202512799_rewards/);
assert.match(soopEventRewardSql, /points_granted integer not null default 50000/);
assert.match(soopEventRewardSql, /on conflict do nothing/);
assert.match(soopEventRewardSql, /and reward\.points_after is null/);
assert.match(soopEventRewardSql, /gacha_s2_deliver_mail/);
assert.match(soopEventRewardSql, /soop-post-202512799:reward-50k/);
assert.match(soopEventRewardSql, /v_reward_total <> v_reward_count::bigint \* 50000/);
assert.match(soopEventRewardSql, /revoke all on table public\.gacha_s2_soop_post_202512799_rewards/);
assert.match(soopEventBatch4Sql, /SOOP event batch 4 target mismatch: expected 9/);
assert.equal((soopEventBatch4Sql.match(/^  \('[a-z0-9]+'\)[,;]$/gm) ?? []).length, 9);
assert.match(soopEventBatch4Sql, /on conflict do nothing/);
assert.match(soopEventBatch4Sql, /soop_post_202512799_batch_4_awarded/);
assert.match(soopEventBatch4Sql, /state\.points \+ 50000/);
assert.match(soopEventBatch4Sql, /\[이벤트\] 참여 보상 지급 완료/);
assert.match(soopEventBatch4Sql, /v_reward_count <> 9 or v_reward_total <> 450000/);
assert.match(soopEventBatch4Sql, /mailbox verification failed: expected 9/);

console.log('renewal database migration tests passed: read-only source, account and bridge carryover, clean game state');

// 신규 가입 시작 포인트 200,000 (운영 이력 20260725175359).
// 소급 지급은 전용 테이블로 멱등성을 잡고, 앞으로의 가입자는 컬럼 기본값으로 처리한다.
const newPlayerPointsSql = await readFile(
  new URL('../supabase/migrations/20260725175359_new_player_starting_points_200k.sql', import.meta.url),
  'utf8',
);
assert.match(newPlayerPointsSql, /lock table public\.gacha_s2_player_states in share row exclusive mode/);
assert.match(newPlayerPointsSql, /points_granted integer not null default 200000/);
assert.match(newPlayerPointsSql, /and reward\.points_after is null/);
assert.match(
  newPlayerPointsSql,
  /alter column points set default 200000/,
  '기본값을 안 바꾸면 앞으로 가입하는 사람은 여전히 5,000 으로 시작한다',
);
assert.match(newPlayerPointsSql, /revoke all on table public\.gacha_s2_new_player_reward_20260726/);

console.log('new player starting points tests passed: idempotent grant, column default');
