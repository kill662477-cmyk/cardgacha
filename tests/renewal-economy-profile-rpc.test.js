import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../supabase/renewal_migration_007_economy_profile.sql', import.meta.url), 'utf8');
const normalized = sql.replace(/\s+/g, ' ');

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

console.log('renewal economy/profile RPC tests passed: support economy, idle rewards, profile commands');
