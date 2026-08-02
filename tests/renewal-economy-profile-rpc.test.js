import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../supabase/renewal_migration_007_economy_profile.sql', import.meta.url), 'utf8');
const normalized = sql.replace(/\s+/g, ' ');
const selectorSql = await readFile(
  new URL('../supabase/migrations/20260727180000_card_selection_tickets.sql', import.meta.url),
  'utf8',
);
const normalizedSelector = selectorSql.replace(/\s+/g, ' ');
const advancedSupportSql = await readFile(
  new URL('../supabase/migrations/20260802162000_advanced_support_pack.sql', import.meta.url),
  'utf8',
);
const normalizedAdvancedSupport = advancedSupportSql.replace(/\s+/g, ' ');

for (const signature of [
  'gacha_s2_purchase_support_pack',
  'gacha_s2_use_support_item',
  'gacha_s2_claim_idle_reward',
  'gacha_s2_set_representative_card',
  'gacha_s2_set_card_lock',
]) assert.match(normalized, new RegExp(`create or replace function public\\.${signature}\\(`));

assert.match(normalized, /for update/);
assert.match(normalized, /gacha_s2_idempotency/);
assert.match(normalized, /VERSION_CONFLICT/);
assert.match(normalized, /gacha_s2_command_audit/);
assert.match(normalized, /gacha_s2_support_draws/);
assert.match(normalized, /guaranteeRates/);
assert.match(normalized, /gacha_s2_draw_pack_for_command/);
assert.match(normalized, /offlineCapHours/);
assert.match(normalized, /gacha_s2_grant_formation_exp/);
assert.doesNotMatch(normalized, /grant execute .* to authenticated/);

assert.match(normalizedSelector, /create or replace function public\.gacha_s2_redeem_card_selector\(/);
assert.match(normalizedSelector, /when 'ssCardSelector' then 'SS'/);
assert.match(normalizedSelector, /when 'sssCardSelector' then 'SSS'/);
assert.match(normalizedSelector, /rarity = v_target_rarity/);
assert.match(normalizedSelector, /and not is_group/);
assert.match(normalizedSelector, /on conflict \(user_id, card_id\) do update/);
assert.match(normalizedSelector, /on conflict \(user_id, card_id\) do nothing/);
assert.match(normalizedSelector, /gacha_s2_idempotency/);
assert.match(normalizedSelector, /gacha_s2_command_audit/);
assert.match(normalizedSelector, /event-only card selection tickets must not enter support-pack rates/);
assert.doesNotMatch(normalizedSelector, /grant execute .* to authenticated/);

assert.match(normalizedAdvancedSupport, /create or replace function public\.gacha_s2_purchase_advanced_support_pack\(/);
assert.match(normalizedAdvancedSupport, /'purchaseAdvancedSupportPack'/);
assert.match(normalizedAdvancedSupport, /'advancedSupportPack'/);
assert.match(normalizedAdvancedSupport, /"price":1500/);
assert.match(normalizedAdvancedSupport, /"tenPrice":15000/);
assert.match(normalizedAdvancedSupport, /"traitReroll":0\.01/);
assert.doesNotMatch(normalizedAdvancedSupport, /grant execute .* to authenticated/);

console.log('renewal economy/profile RPC tests passed: support economy, idle rewards, profile commands');
