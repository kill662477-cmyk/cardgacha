import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { COMBAT_POWER_LEADERS, COMBAT_RANKING_RULES, buildCombatPowerRanking } from '../src/renewal/rankings.js';

const rankingControllerSource = await readFile(new URL('../src/renewal/ranking-controller.js', import.meta.url), 'utf8');
const rankingStyles = await readFile(new URL('../styles/renewal/main.css', import.meta.url), 'utf8');

assert.match(rankingControllerSource, /class="ranking-podium-head"/);
assert.match(rankingControllerSource, /class="ranking-podium-name"/);
assert.match(rankingStyles, /\.ranking-podium-head \{[^}]*grid-area: head;[^}]*justify-content: space-between;/);
assert.match(rankingStyles, /\.ranking-podium-name \{[^}]*overflow-wrap: anywhere;[^}]*-webkit-line-clamp: 2;/);
assert.match(rankingStyles, /\.ranking-podium-copy \.ranking-inline-medal \{[^}]*flex: none;/);

assert.equal(COMBAT_POWER_LEADERS.length, 50);
assert.equal(new Set(COMBAT_POWER_LEADERS.map((entry) => entry.nickname)).size, 50);
assert.ok(COMBAT_POWER_LEADERS.every((entry, index) => index === 0 || COMBAT_POWER_LEADERS[index - 1].power > entry.power));

const outside = buildCombatPowerRanking('내계정', 14_159);
assert.equal(outside.leaders.length, COMBAT_RANKING_RULES.visibleCount);
assert.ok(outside.player.rank > 50 && outside.player.rank <= outside.population);
assert.ok(outside.player.topPercent > 0 && outside.player.topPercent <= 100);
assert.ok(outside.powerToTopFifty > 0);

const champion = buildCombatPowerRanking('내계정', 1_000_000);
assert.equal(champion.player.rank, 1);
assert.equal(champion.powerToTopFifty, 0);
assert.equal(champion.leaders[0].nickname, '내계정');
const hellChampion = buildCombatPowerRanking('HELL정복자', 1_000_001, undefined, true);
assert.equal(hellChampion.player.hellConqueror, true);
assert.equal(hellChampion.leaders[0].hellConqueror, true);

console.log(`renewal ranking tests passed: ${outside.player.rank}/${outside.population}, top ${outside.player.topPercent.toFixed(1)}%`);
