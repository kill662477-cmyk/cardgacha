import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const at = (...parts) => path.join(root, ...parts);
const exists = (...parts) => fs.existsSync(at(...parts));

for (const required of [
  'index.html',
  'src/renewal/app.js',
  'styles/renewal/main.css',
  'data/renewal-cards.json',
  'assets/card-back.jpg',
  'assets/renewal/brand/card-gacha-s2-symbol.png',
  'supabase/renewal_migration_001_accounts_reset.sql',
  'supabase/renewal_migration_999_drop_season1.sql',
]) assert.equal(exists(...required.split('/')), true, `missing season2 file: ${required}`);

for (const legacy of [
  'renewal.html',
  'api',
  'lib',
  'donation-bridge.html',
  'maintenance.html',
  'data/cards.json',
  'data/races.json',
  'assets/frames',
  'assets/fx',
  'assets/packs',
]) assert.equal(exists(...legacy.split('/')), false, `season1-only path remains: ${legacy}`);

const index = fs.readFileSync(at('index.html'), 'utf8');
assert.match(index, /<title>카드가챠 시즌2<\/title>/);
assert.match(index, /src\/renewal\/app\.js/);
assert.doesNotMatch(index, /api\//);

const cards = JSON.parse(fs.readFileSync(at('data', 'renewal-cards.json'), 'utf8'));
const catalogFiles = [...new Set(cards.map((card) => card.file))].sort();
const assetFiles = fs.readdirSync(at('assets', 'cards')).sort();
assert.equal(cards.length, 212);
assert.deepEqual(assetFiles, catalogFiles, 'assets/cards must exactly match the season2 catalog');

const staticSources = [
  'index.html',
  'styles/renewal/main.css',
  'src/renewal/app.js',
  'src/renewal/card-visual.js',
  'src/renewal/fx-controller.js',
];
const referencedAssets = new Set();
for (const file of staticSources) {
  const source = fs.readFileSync(at(...file.split('/')), 'utf8');
  for (const match of source.matchAll(/assets\/[A-Za-z0-9_./-]+\.(?:avif|jpe?g|mp3|mp4|png|svg|webm|webp)/g)) {
    if (!match[0].includes('${')) referencedAssets.add(match[0]);
  }
}
for (const asset of referencedAssets) assert.equal(exists(...asset.split('/')), true, `missing referenced asset: ${asset}`);

const migrations = fs.readdirSync(at('supabase')).sort();
assert.deepEqual(migrations, [
  'renewal_migration_001_accounts_reset.sql',
  'renewal_migration_999_drop_season1.sql',
]);

console.log(`renewal repository hygiene tests passed: ${cards.length} cards, ${referencedAssets.size} static assets, no season1 app paths`);
