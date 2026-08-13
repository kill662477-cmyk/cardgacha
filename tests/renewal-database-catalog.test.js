import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { BALANCE_VERSION } from '../src/renewal/config.js';
import { buildBalancePayload, buildCatalogMigration, loadCards } from '../scripts/build-renewal-database-catalog.js';

const cards = loadCards();
const sql = await readFile(new URL('../supabase/renewal_migration_002_catalog_and_balance.sql', import.meta.url), 'utf8');
const normalizedSql = sql.replace(/\r\n/g, '\n');
const normalized = normalizedSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();

// migration 002 is immutable after production deployment. Runtime balance hotfixes
// must be new migrations, so compare current payload after removing only the
// explicitly patched fields instead of rewriting historical seed SQL.
const seededPayload = JSON.parse(normalizedSql.match(/\$balance\$([\s\S]*?)\$balance\$::jsonb/)?.[1] ?? 'null');
const currentPayload = structuredClone(buildBalancePayload());
currentPayload.supportPack.items.cardExpPotion = seededPayload.supportPack.items.cardExpPotion;
currentPayload.supportPack.items.energySmall = seededPayload.supportPack.items.energySmall;
currentPayload.supportPack.items.adventureRunReset = seededPayload.supportPack.items.adventureRunReset;
delete currentPayload.supportPack.items.traitReroll;
delete currentPayload.supportItems.traitReroll;
delete currentPayload.supportItems.raceChangeSelector;
delete currentPayload.directSupportItems;
delete currentPayload.advancedSupportPack;
delete currentPayload.supportPack.tenGuarantee;
currentPayload.supportItemDismantle = seededPayload.supportItemDismantle;
currentPayload.supportPack.rareItems = seededPayload.supportPack.rareItems;
currentPayload.supportPack.guaranteeRates = seededPayload.supportPack.guaranteeRates;
assert.deepEqual(currentPayload, seededPayload, 'catalog seed drift outside approved supplemental balance migration');
const traitMigration = await readFile(new URL('../supabase/migrations/20260802160000_random_trait_reroll_ticket.sql', import.meta.url), 'utf8');
assert.match(traitMigration, /supportPack,items,traitReroll/);
assert.match(traitMigration, /'0\.001'::jsonb/);
assert.match(traitMigration, /supportPack,items,cardExpPotion/);
assert.match(traitMigration, /'9\.999'::jsonb/);
const raceChangeMigration = await readFile(new URL('../supabase/migrations/20260813153000_race_change_selector.sql', import.meta.url), 'utf8');
assert.match(raceChangeMigration, /"price":20000000/);
assert.match(raceChangeMigration, /add column if not exists race_override text/);
assert.match(raceChangeMigration, /gacha_s2_purchase_fixed_support_item/);
assert.match(raceChangeMigration, /set race_override = v_race/);
const safeRaceChangeMigration = await readFile(new URL('../supabase/migrations/20260813171500_reenable_race_change_selector_safely.sql', import.meta.url), 'utf8');
assert.match(safeRaceChangeMigration, /gacha_s2_strip_zero_race_selector_key/);
assert.match(safeRaceChangeMigration, /before insert or update of support_items/);
assert.match(safeRaceChangeMigration, /new\.support_items := new\.support_items - 'raceChangeSelector'/);
assert.doesNotMatch(safeRaceChangeMigration, /set support_items = jsonb_set\(/, 'safe re-enable must not seed a zero key into every account');
const atomicRaceChangeMigration = await readFile(new URL('../supabase/migrations/20260813180000_race_change_selector_atomic_compat.sql', import.meta.url), 'utf8');
assert.match(atomicRaceChangeMigration, /applyImmediately/);
assert.match(atomicRaceChangeMigration, /p_target_card_id text/);
assert.match(atomicRaceChangeMigration, /set race_override = p_race/);
assert.match(atomicRaceChangeMigration, /support_items = support_items - 'raceChangeSelector'/);
assert.match(atomicRaceChangeMigration, /v_config := v_config #- '\{supportItems,raceChangeSelector\}'/);
assert.doesNotMatch(atomicRaceChangeMigration, /\{supportItems,raceChangeSelector\}[\s\S]{0,200}jsonb_set/, 'legacy support-item catalog must stay unchanged');
const raceSnapshotExCompatMigration = await readFile(new URL('../supabase/migrations/20260813181000_race_snapshot_ex_compat.sql', import.meta.url), 'utf8');
assert.match(raceSnapshotExCompatMigration, /catalog\.rarity = ''EX'' or catalog\.is_group/);
assert.match(raceSnapshotExCompatMigration, /then null else coalesce\(c\.race_override/);
const supportBalanceMigration = await readFile(new URL('../supabase/migrations/20260802163000_reduce_rare_support_rewards.sql', import.meta.url), 'utf8');
assert.match(supportBalanceMigration, /'destructionGuard', 30/);
assert.match(supportBalanceMigration, /'premiumTicket', 75/);
assert.match(supportBalanceMigration, /'adventureRunReset', 600/);
assert.match(supportBalanceMigration, /'quickBattleReset', 200/);
assert.match(supportBalanceMigration, /\{supportPack,tenGuarantee\}[^\n]*'false'::jsonb/);
assert.match(supportBalanceMigration, /\{advancedSupportPack,tenGuarantee\}[^\n]*'false'::jsonb/);
const adventureResetRateMigration = await readFile(new URL('../supabase/migrations/20260802171000_reduce_adventure_reset_pack_rates.sql', import.meta.url), 'utf8');
assert.match(adventureResetRateMigration, /'adventureRunReset', 0\.03125/);
assert.match(adventureResetRateMigration, /'adventureRunReset', 0\.5/);
assert.match(adventureResetRateMigration, /'energySmall', 14\.21875/);
assert.match(adventureResetRateMigration, /'energyLarge', 14\.5/);
assert.equal(buildBalancePayload().balanceVersion, BALANCE_VERSION);
assert.match(normalized, /create table if not exists public\.gacha_s2_balance_versions/);
assert.match(normalized, /create table if not exists public\.gacha_s2_card_catalog/);
assert.match(normalized, /create unique index if not exists uq_gacha_s2_one_active_balance/);
assert.match(normalized, /where active/);
assert.match(normalized, /rarity in \('f','e','d','c','b','a','s','ss','sss','ex'\)/);
assert.match(normalized, /rarity = 'ex' and race = 'ex' and archetype is null and is_group/);
assert.match(normalized, /v_total <> 235/);
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
// 002 는 배포 후 고정이다. 여기 씨앗은 235장에서 멈춰 있고, 그 뒤 추가된 카드는
// 각자 보충 마이그레이션에서 들어온다. 002 를 다시 만들면 잔액 payload 까지
// 덮어써서 위쪽 drift 검사가 깨진다.
assert.equal(rows.length, 235, 'migration 002 is immutable - new cards belong in supplemental migrations');
const seededIds = rows.map((line) => line.match(/^  \('([^']+)'/)?.[1]);

// 002 이후 추가된 카드. 카드를 더 넣을 때마다 마이그레이션 경로와 id 를 함께 적는다.
const supplementalCardMigrations = [
  ['20260810100443_add_jidudu14_juharang18_sss_cards.sql', ['jidudu-14', 'juharang-18']],
];
const supplementalIds = [];
for (const [file, ids] of supplementalCardMigrations) {
  const migration = await readFile(new URL(`../supabase/migrations/${file}`, import.meta.url), 'utf8');
  for (const id of ids) {
    assert.ok(migration.includes(`('${id}'`), `${file} 에 ${id} insert 가 없다`);
    // 002 씨앗에 이미 있으면 중복이다.
    assert.ok(!seededIds.includes(id), `${id} 는 002 에 이미 있다 - 보충 목록에서 빼야 한다`);
    supplementalIds.push(id);
  }
}
// 002 씨앗 + 보충분이 카드 데이터와 정확히 일치해야 한다. 어긋나면 DB 에 없는 카드가
// 화면에 뜨거나, 뽑기에서 나온 카드가 저장에 실패한다.
const byName = (left, right) => left.localeCompare(right);
assert.deepEqual(
  [...seededIds, ...supplementalIds].sort(byName),
  [...cards.map((card) => card.id)].sort(byName),
);
assert.equal((normalizedSql.match(/'[0-9a-f]{64}'/g) ?? []).length >= 4, true, 'config and catalog hashes must be embedded and verified');

console.log(`renewal database catalog tests passed: ${cards.length} cards, balance ${BALANCE_VERSION}, deterministic seed`);
