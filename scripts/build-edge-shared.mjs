import { copyFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const target = path.join(root, 'supabase', 'functions', '_shared', 'generated');
const sources = [
  ['src/renewal/config.js', 'config.js'],
  ['src/renewal/battle.js', 'battle.js'],
  ['src/renewal/collection.js', 'collection.js'],
  ['src/renewal/worldboss-schedule.js', 'worldboss-schedule.js'],
  ['src/renewal/worldboss.js', 'worldboss.js'],
  ['src/renewal/service-contract.js', 'service-contract.js'],
  ['src/renewal/server-command-router.js', 'server-command-router.js'],
  ['data/renewal-cards.json', 'cards.json'],
];

await mkdir(target, { recursive: true });
await Promise.all(sources.map(([source, destination]) => (
  copyFile(path.join(root, source), path.join(target, destination))
)));
console.log(`edge shared modules synchronized: ${sources.length}`);
