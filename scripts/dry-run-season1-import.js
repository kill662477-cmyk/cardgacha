import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { analyzeSeason1Export } from '../src/renewal/season1-import.js';

function argument(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

const input = argument('--input');
const rankingSnapshotInput = argument('--ranking-snapshot');
const output = argument('--report');
const sampleSize = Number(argument('--sample') ?? 10);
if (!input || /^https?:/i.test(input)) {
  console.error('Usage: node scripts/dry-run-season1-import.js --input <local-export.json> --ranking-snapshot <top50.json> [--sample 10] [--report <report.json>]');
  process.exitCode = 2;
} else {
  const [source, cards, rankingSnapshot] = await Promise.all([
    readFile(resolve(input), 'utf8').then(JSON.parse),
    readFile(new URL('../data/renewal-cards.json', import.meta.url), 'utf8').then(JSON.parse),
    rankingSnapshotInput
      ? readFile(resolve(rankingSnapshotInput), 'utf8').then(JSON.parse)
      : Promise.resolve(null),
  ]);
  const report = analyzeSeason1Export(source, cards, {
    sampleSize,
    importedAt: Date.now(),
    rankingSnapshot: rankingSnapshot ?? source.rankingSnapshot,
  });
  const printable = { ok: report.ok, importedAt: report.importedAt, summary: report.summary, sampleIds: report.sampleIds, issues: report.issues };
  console.log(JSON.stringify(printable, null, 2));
  if (output) await writeFile(resolve(output), `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  if (!report.ok) process.exitCode = 1;
}
