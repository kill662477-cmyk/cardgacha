import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const edgePairs = [
  ['src/renewal/config.js', 'supabase/functions/_shared/generated/config.js'],
  ['src/renewal/worldboss-rules.js', 'supabase/functions/_shared/generated/worldboss-rules.js'],
  ['src/renewal/battle.js', 'supabase/functions/_shared/generated/battle.js'],
  ['src/renewal/collection.js', 'supabase/functions/_shared/generated/collection.js'],
  ['src/renewal/worldboss-schedule.js', 'supabase/functions/_shared/generated/worldboss-schedule.js'],
  ['src/renewal/worldboss.js', 'supabase/functions/_shared/generated/worldboss.js'],
  ['src/renewal/service-contract.js', 'supabase/functions/_shared/generated/service-contract.js'],
  ['src/renewal/server-command-router.js', 'supabase/functions/_shared/generated/server-command-router.js'],
  ['data/renewal-cards.json', 'supabase/functions/_shared/generated/cards.json'],
];

function git(args) {
  return execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
}

const status = git(['status', '--porcelain']);
if (status) throw new Error(`배포 중단: 미커밋 변경이 있습니다.\n${status}`);

git(['fetch', 'origin', 'main']);
const localHead = git(['rev-parse', 'HEAD']);
const remoteHead = git(['rev-parse', 'origin/main']);
if (localHead !== remoteHead) {
  throw new Error(`배포 중단: 로컬 HEAD(${localHead.slice(0, 7)})와 origin/main(${remoteHead.slice(0, 7)})이 다릅니다.`);
}

const staleGenerated = edgePairs.filter(([source, generated]) => (
  !readFileSync(path.join(root, source)).equals(readFileSync(path.join(root, generated)))
));
if (staleGenerated.length) {
  throw new Error(`배포 중단: Edge 생성본이 오래됐습니다. npm run build:edge-shared 필요.\n${staleGenerated.map(([source, generated]) => `${source} != ${generated}`).join('\n')}`);
}

console.log(`deployment preflight passed: ${localHead.slice(0, 7)}, clean main, ${edgePairs.length} Edge files synced`);
