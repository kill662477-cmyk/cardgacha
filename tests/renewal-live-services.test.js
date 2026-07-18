import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = (await readFile(new URL('../supabase/renewal_migration_009_live_services.sql', import.meta.url), 'utf8'))
  .replace(/\s+/g, ' ');
const edge = await readFile(new URL('../supabase/functions/soop-bridge/index.ts', import.meta.url), 'utf8');
const client = await readFile(new URL('../src/renewal/soop-bridge.js', import.meta.url), 'utf8');
const worldBoss = await readFile(new URL('../src/renewal/worldboss-controller.js', import.meta.url), 'utf8');
const ranking = await readFile(new URL('../src/renewal/ranking-controller.js', import.meta.url), 'utf8');

assert.match(sql, /create or replace function public\.gacha_s2_get_power_ranking/);
assert.match(sql, /set power_snapshot = p_verified_power, power_snapshot_at = now\(\)/);
assert.match(sql, /order by state\.power_snapshot desc, state\.power_snapshot_at asc nulls last, state\.user_id/);
assert.match(sql, /where rank <= 20/);
assert.match(sql, /when v_rank <= 50 or v_top_fifty_power = 0 then 0/);

assert.match(sql, /action in \('BALLOON_GIFTED', 'BATTLE_MISSION_GIFTED'\)/);
assert.doesNotMatch(sql, /FINISHED|SETTLED/);
assert.match(sql, /v_points := p_amount \* 3/);
assert.match(sql, /bridge\.soop_id = trim\(p_recipient_soop_id\)/);
assert.match(sql, /pg_advisory_xact_lock/);
assert.match(sql, /donation event id reused with different payload/);
assert.match(sql, /revision = revision \+ 1/);
assert.match(sql, /gacha_s2_bridge_rate_limits/);
assert.match(sql, /gacha_s2_consume_soop_exchange/);

assert.match(edge, /SOOP_BRIDGE_SESSION_SECRET/);
assert.match(edge, /SOOP_BRIDGE_RATE_LIMIT_PEPPER/);
assert.match(edge, /SOOP_BRIDGE_ENCRYPTION_KEY/);
assert.match(edge, /AES-GCM/);
assert.match(edge, /type: 'soop-oauth'/);
assert.match(edge, /gacha_s2_apply_soop_donation/);
assert.match(edge, /eventAction/);
assert.doesNotMatch(edge, /['"]FINISHED['"]|['"]SETTLED['"]/);

assert.match(client, /new Set\(\['BALLOON_GIFTED', 'BATTLE_MISSION_GIFTED'\]\)/);
assert.match(client, /recipient\(message\) \|\| state\.credentials\?\.soopId/);
assert.doesNotMatch(client, /localStorage/);
assert.match(worldBoss, /subscribeWorldBoss/);
assert.match(worldBoss, /refreshServerStatus/);
assert.match(ranking, /gameService\.getPowerRanking/);

console.log('renewal live services tests passed: server ranking, Realtime world boss, hardened SOOP bridge');
