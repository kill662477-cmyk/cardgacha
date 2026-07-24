import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { BALANCE_VERSION } from '../src/renewal/config.js';
import { buildBalancePayload, buildCatalogMigration, loadCards } from '../scripts/build-renewal-database-catalog.js';

const cards = loadCards();
const sql = await readFile(new URL('../supabase/renewal_migration_002_catalog_and_balance.sql', import.meta.url), 'utf8');
const generated = buildCatalogMigration(cards);
const normalizedSql = sql.replace(/\r\n/g, '\n');
const normalized = normalizedSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();

assert.equal(normalizedSql, generated, 'catalog migration must be regenerated after card or balance changes');
assert.equal(buildBalancePayload().balanceVersion, BALANCE_VERSION);
assert.match(normalized, /create table if not exists public\.gacha_s2_balance_versions/);
assert.match(normalized, /create table if not exists public\.gacha_s2_card_catalog/);
assert.match(normalized, /create unique index if not exists uq_gacha_s2_one_active_balance/);
assert.match(normalized, /where active/);
assert.match(normalized, /rarity in \('f','e','d','c','b','a','s','ss','sss','ex'\)/);
assert.match(normalized, /rarity = 'ex' and race = 'ex' and archetype is null and is_group/);
assert.match(normalized, /v_total <> 224/);
assert.match(normalized, /count\(distinct archetype\) <> 8/);
assert.match(normalized, /gacha_s2_player_cards_catalog_fk/);
assert.match(normalized, /foreign key \(card_id\) references public\.gacha_s2_card_catalog\(card_id\)/);
assert.match(normalized, /alter table public\.gacha_s2_balance_versions enable row level security/);
assert.match(normalized, /alter table public\.gacha_s2_card_catalog enable row level security/);
assert.match(normalized, /revoke all on table public\.gacha_s2_card_catalog from public, anon, authenticated/);
assert.doesNotMatch(normalized, /grant (?:select|insert|update|delete|all).*gacha_s2_card_catalog.*(?:anon|authenticated)/);

const catalogSeed = normalizedSql.match(/insert into public\.gacha_s2_card_catalog \([\s\S]*?\)\nvalues\n([\s\S]*?)\non conflict \(card_id\)/i)?.[1];
assert.ok(catalogSeed, 'catalog seed block missing');
const rows = catalogSeed.split('\n').filter((line) => line.startsWith('  ('));
assert.equal(rows.length, 224);
const seededIds = rows.map((line) => line.match(/^  \('([^']+)'/)?.[1]);
assert.deepEqual(seededIds, [...cards.map((card) => card.id)].sort((left, right) => left.localeCompare(right)));
assert.equal((normalizedSql.match(/'[0-9a-f]{64}'/g) ?? []).length >= 4, true, 'config and catalog hashes must be embedded and verified');

console.log(`renewal database catalog tests passed: ${cards.length} cards, balance ${BALANCE_VERSION}, deterministic seed`);
