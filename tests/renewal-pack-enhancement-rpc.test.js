import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../supabase/renewal_migration_004_pack_and_enhancement.sql', import.meta.url), 'utf8');
const supportBalanceSql = await readFile(new URL('../supabase/migrations/20260722000058_support_pack_probability_balance.sql', import.meta.url), 'utf8');
const sameCardMaterialSql = await readFile(new URL('../supabase/migrations/20260723000068_allow_same_card_enhancement_material.sql', import.meta.url), 'utf8');
const normalized = sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const supportBalance = supportBalanceSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const sameCardMaterial = sameCardMaterialSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const pack = normalized.slice(
  normalized.indexOf('create or replace function public.gacha_s2_purchase_pack'),
  normalized.indexOf('create or replace function public.gacha_s2_enhance_card'),
);
const enhance = normalized.slice(normalized.indexOf('create or replace function public.gacha_s2_enhance_card'));

for (const table of ['gacha_s2_pack_draws', 'gacha_s2_enhancement_results']) {
  assert.match(normalized, new RegExp(`create table if not exists public\\.${table}`));
  assert.match(normalized, new RegExp(`alter table public\\.${table} enable row level security`));
  assert.match(normalized, new RegExp(`revoke all on table public\\.${table} from public, anon, authenticated`));
}
assert.match(normalized, /alter table public\.gacha_s2_command_audit add column if not exists server_seed bigint/);
assert.match(normalized, /gen_random_bytes\(4\)/);
assert.match(normalized, /digest\(p_seed::text \|\| ':' \|\| p_counter::text, 'sha256'\)/);
assert.match(normalized, /server_seed bigint not null check \(server_seed between 0 and 4294967295\)/);

assert.match(pack, /p_quantity integer/);
assert.match(pack, /p_quantity not in \(1, 10\)/);
assert.match(pack, /p_product_id = 'race'.*p_race not in \('저그','테란','프로토스'\)/);
assert.match(pack, /select revision, points into v_revision, v_points from public\.gacha_s2_player_states.*for update/);
assert.match(pack, /select config into v_config from public\.gacha_s2_balance_versions where active/);
assert.match(pack, /v_total_cost := v_pack_price \* p_quantity/);
assert.match(pack, /v_total_draws := v_pack_count \* p_quantity/);
assert.match(pack, /jsonb_each_text\(v_pack->'rates'\)/);
assert.match(pack, /sum\(weight\) over \(order by rarity_order\)/);
assert.match(pack, /where rarity = v_rarity and not is_group and \(p_product_id <> 'race' or race = p_race\)/);
assert.match(pack, /on conflict \(user_id, card_id\) do update set copies = public\.gacha_s2_player_cards\.copies \+ 1/);
assert.match(pack, /insert into public\.gacha_s2_collection_records/);
assert.match(pack, /insert into public\.gacha_s2_pack_draws/);
assert.match(pack, /set points = points - v_total_cost, shop_transactions = shop_transactions \+ 1, revision = revision \+ 1/);
assert.match(pack, /insert into public\.gacha_s2_idempotency/);
assert.match(pack, /insert into public\.gacha_s2_command_audit/);

const packReplay = pack.indexOf('select * into v_previous from public.gacha_s2_idempotency');
const packRevision = pack.indexOf('if p_expected_revision <> v_revision then');
const packDraw = pack.indexOf('insert into public.gacha_s2_player_cards');
const packCommit = pack.indexOf('insert into public.gacha_s2_idempotency');
assert.ok(packReplay >= 0 && packReplay < packRevision, 'pack replay must precede revision conflict');
assert.ok(packRevision < packDraw && packDraw < packCommit, 'pack validation must precede atomic draws and replay commit');

assert.match(enhance, /p_material_card_ids text\[\]/);
assert.match(enhance, /p_target_enhancement not between 1 and 9/);
assert.match(enhance, /select revision, points, support_items into v_revision, v_points, v_support_items.*for update/);
assert.match(enhance, /v_target\.rarity = 'ex'/);
assert.match(enhance, /p_target_enhancement <> v_target\.enhancement \+ 1/);
assert.match(enhance, /'exprequirements'->>\(v_target\.enhancement\)/);
assert.match(enhance, /jsonb_array_elements\(v_config->'materialrules'->\(v_target\.rarity\)\)/);
assert.match(enhance, /req\.requested_count > owned\.copies - 1/);
assert.match(enhance, /owned\.locked and req\.card_id <> p_card_id/);
assert.match(enhance, /p_target_enhancement = 9.*plusninepointcost/s);
assert.match(enhance, /v_booster in \('enhance5','enhance10'\) and p_target_enhancement < 4/);
assert.match(enhance, /v_booster = 'destructionguard' and p_target_enhancement < 7/);
assert.match(enhance, /'basesuccessrates'->>\(p_target_enhancement\)/);
assert.match(enhance, /'destroyrates'->>\(p_target_enhancement\)/);
assert.match(enhance, /'raritypenalties'->>v_target\.rarity/);
assert.match(enhance, /v_roll := public\.gacha_s2_seed_roll\(v_seed, 0\) \* 100/);
assert.match(enhance, /if v_roll < v_success_rate then.*elsif v_roll < v_success_rate \+ v_destroy_rate then/s);
assert.match(enhance, /if v_booster = 'destructionguard' then v_outcome := 'fail'.*v_blocked := true/s);
assert.match(enhance, /set copies = owned\.copies - req\.requested_count/);
assert.match(enhance, /set enhancement = p_target_enhancement, card_exp = 0/);
assert.match(enhance, /set enhancement = 0, card_exp = 0/);
assert.doesNotMatch(enhance, /delete from public\.gacha_s2_player_cards/);
assert.match(enhance, /support_items = v_support_items, enhancement_attempts = enhancement_attempts \+ 1, revision = revision \+ 1/);
assert.match(enhance, /insert into public\.gacha_s2_enhancement_results/);
assert.match(enhance, /insert into public\.gacha_s2_idempotency/);
assert.match(enhance, /insert into public\.gacha_s2_command_audit/);

const enhanceReplay = enhance.indexOf('select * into v_previous from public.gacha_s2_idempotency');
const enhanceRevision = enhance.indexOf('if p_expected_revision <> v_revision then');
const materialConsume = enhance.indexOf('set copies = owned.copies - req.requested_count');
const enhanceCommit = enhance.indexOf('insert into public.gacha_s2_idempotency');
assert.ok(enhanceReplay >= 0 && enhanceReplay < enhanceRevision, 'enhancement replay must precede revision conflict');
assert.ok(enhanceRevision < materialConsume && materialConsume < enhanceCommit, 'enhancement validation must precede atomic consumption and replay commit');

assert.doesNotMatch(normalized, /p_request_hash|p_server_seed|p_roll|p_outcome|p_draws/);
for (const fn of [
  'gacha_s2_purchase_pack\\(uuid, bigint, text, text, integer, text\\)',
  'gacha_s2_enhance_card\\(uuid, bigint, text, text, integer, text\\[\\], text\\)',
]) {
  assert.match(normalized, new RegExp(`revoke all on function public\\.${fn} from public, anon, authenticated`));
  assert.match(normalized, new RegExp(`grant execute on function public\\.${fn} to service_role`));
  assert.doesNotMatch(normalized, new RegExp(`grant execute on function public\\.${fn} to (?:anon|authenticated)`));
}

assert.match(supportBalance, /2026\.07\.22-support-pack-balance-1/);
assert.match(supportBalance, /"energysmall":14/);
assert.match(supportBalance, /"energymedium":8/);
assert.match(supportBalance, /"energylarge":2/);
assert.match(supportBalance, /"destructionguard":5/);
assert.match(supportBalance, /"energylarge":7/);
assert.match(supportBalance, /"destructionguard":6/);
assert.match(supportBalance, /update public\.gacha_s2_balance_versions set active = false where active/);

assert.match(sameCardMaterial, /pg_get_functiondef\(v_signature\)/);
assert.match(sameCardMaterial, /owned\.locked and req\.card_id <> p_card_id/);
assert.match(sameCardMaterial, /owned\.copies - 1 validation still preserves the target's base copy|locked-material guard was not found/);

console.log('renewal pack/enhancement RPC tests passed: server RNG, atomic economy, replay, revision, service-role boundary');
