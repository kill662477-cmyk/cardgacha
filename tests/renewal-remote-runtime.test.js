import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { mergeServerSnapshot, readRemoteConfig } from '../src/renewal/remote-runtime.js';

assert.equal(readRemoteConfig({}).enabled, false);
assert.equal(readRemoteConfig({
  supabaseUrl: 'https://project.supabase.co',
  supabasePublishableKey: 'sb_publishable_test',
}).enabled, true);

const merged = mergeServerSnapshot({
  revision: 7,
  clearedStage: 12,
  worldBoss: {},
}, {
  currentStage: 4,
  autoBattle: true,
  soundEnabled: false,
  worldBoss: { eventId: 'local-placeholder' },
});
assert.equal(merged.revision, 7);
assert.equal(merged.currentStage, 4);
assert.equal(merged.autoBattle, true);
assert.equal(merged.soundEnabled, false);
assert.equal(merged.worldBoss.eventId, 'local-placeholder');

const app = await readFile(new URL('../src/renewal/app.js', import.meta.url), 'utf8');
for (const command of [
  'UPDATE_FORMATION', 'CLAIM_ADVENTURE_REWARDS', 'CLAIM_QUICK_BATTLE',
  'PURCHASE_PACK', 'PURCHASE_SUPPORT_PACK', 'USE_SUPPORT_ITEM', 'ENHANCE_CARD',
  'START_ADVENTURE_RUN', 'FINISH_ADVENTURE_RUN', 'START_MINIGAME', 'FINISH_MINIGAME',
  'ATTACK_WORLD_BOSS', 'CLAIM_WORLD_BOSS_REWARD', 'SET_REPRESENTATIVE_CARD', 'SET_CARD_LOCK',
]) assert.match(app, new RegExp(`GAME_COMMAND_TYPES\\.${command}`));
assert.match(app, /if \(remoteMode\) await requireRemoteSnapshot\(\)/);
assert.match(app, /applyServerSnapshot\(response\.snapshot\)/);

console.log('renewal remote runtime tests passed: opt-in config, server snapshots, all mutation command paths');
