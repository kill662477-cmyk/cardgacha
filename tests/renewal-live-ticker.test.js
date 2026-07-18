import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  LIVE_EVENT_TTL_MS, liveEventMarkup, mergeLiveEvents, normalizeLiveEvent,
} from '../src/renewal/live-ticker-controller.js';

const now = Date.parse('2026-07-19T03:00:00.000Z');
const draw = {
  id: 1,
  event_type: 'card_draw',
  nickname: 'MSTZ',
  card_id: 'tomato-1',
  member: '토마토',
  rarity: 'SS',
  enhancement: null,
  created_at: new Date(now - 1000).toISOString(),
};
assert.equal(normalizeLiveEvent(draw).rarity, 'SS');
assert.equal(normalizeLiveEvent({ ...draw, rarity: 'A' }), null, 'only S/SS/SSS draws enter the ticker');
assert.equal(normalizeLiveEvent({
  ...draw, event_type: 'nine_star_success', rarity: 'F', enhancement: 9,
}).enhancement, 9, 'every combat rarity can announce a +9 success');
assert.equal(mergeLiveEvents([{ ...draw, created_at: new Date(now - LIVE_EVENT_TTL_MS - 1).toISOString() }], now).length, 0);
assert.equal(mergeLiveEvents([draw, { ...draw, id: 2, created_at: new Date(now - 2000).toISOString() }], now).length, 1, 'Realtime/local echo is deduplicated');
assert.match(liveEventMarkup(normalizeLiveEvent({ ...draw, nickname: '<img onerror=1>' })), /&lt;img onerror=1&gt;/);

const sql = (await readFile(new URL('../supabase/renewal_migration_011_live_event_ticker.sql', import.meta.url), 'utf8'))
  .replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
assert.match(sql, /create table if not exists public\.gacha_s2_live_events/);
assert.match(sql, /new\.rarity not in \('s','ss','sss'\)/);
assert.match(sql, /new\.target_enhancement <> 9/);
assert.match(sql, /after insert on public\.gacha_s2_pack_draws/);
assert.match(sql, /after insert on public\.gacha_s2_enhancement_results/);
assert.match(sql, /alter publication supabase_realtime add table public\.gacha_s2_live_events/);
assert.match(sql, /to authenticated using \(created_at >= now\(\) - interval '10 minutes'\)/);
assert.doesNotMatch(sql, /grant (?:insert|update|delete).*authenticated/);

console.log('renewal live ticker tests passed: S-SSS draws, all +9 successes, TTL, dedupe, RLS, Realtime');
