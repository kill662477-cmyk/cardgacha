import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { escapeHtml } from '../src/renewal/html.js';

assert.equal(escapeHtml(`<img src=x onerror="alert('x')"> &`), '&lt;img src=x onerror=&quot;alert(&#39;x&#39;)&quot;&gt; &amp;');
assert.equal(escapeHtml(null), '');

const clientFiles = [
  'index.html',
  'src/renewal/app.js',
  'src/renewal/ranking-controller.js',
  'src/renewal/worldboss-controller.js',
];
const secretPattern = /service[_ -]?role|supabase_service|bridge[_ -]?key|admin[_ -]?key|secret[_ -]?key|private[_ -]?key|eyJ[a-zA-Z0-9_-]{20,}/i;
for (const file of clientFiles) {
  const source = await readFile(new URL(`../${file}`, import.meta.url), 'utf8');
  assert.equal(secretPattern.test(source), false, `${file} must not contain server secrets`);
}

const rankingSource = await readFile(new URL('../src/renewal/ranking-controller.js', import.meta.url), 'utf8');
const worldBossSource = await readFile(new URL('../src/renewal/worldboss-controller.js', import.meta.url), 'utf8');
assert.match(rankingSource, /escapeHtml\(entry\.nickname\)/);
assert.match(worldBossSource, /escapeHtml\(row\.name\)/);
assert.match(worldBossSource, /escapeHtml\(name\)/);

console.log('renewal security tests passed: secret scan, nickname HTML escaping');
