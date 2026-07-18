import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createLocalGameService, GAME_SERVICE_METHODS } from '../src/renewal/local-game-service.js';

const storage = new Map();
globalThis.localStorage = {
  getItem: (key) => storage.get(key) ?? null,
  setItem: (key, value) => storage.set(key, value),
  removeItem: (key) => storage.delete(key),
};

let now = Date.UTC(2026, 6, 17, 12, 0, 0);
const randomValues = [0.125, 0.75];
const service = createLocalGameService({
  reset: true,
  clock: { now: () => now },
  rng: { next: () => randomValues.shift() ?? 0.5 },
});

GAME_SERVICE_METHODS.forEach((method) => assert.equal(typeof service[method], 'function', `${method} must exist`));
assert.equal(service.now(), now);
assert.equal(service.random(), 0.125);
assert.equal(service.random(), 0.75);

const state = service.loadSnapshot();
assert.equal(state.lastEnergyAt, now);
assert.equal(state.revision, 0);
service.updateFormation(state);
assert.equal(state.revision, 1);

const replacement = { ...state, points: 4321 };
service.purchasePack(replacement);
assert.equal(service.loadSnapshot(), replacement);
assert.equal(service.loadSnapshot().points, 4321);
assert.equal(service.loadSnapshot().revision, 2);
assert.deepEqual(service.getPowerRanking((snapshot) => ({ nickname: snapshot.nickname, points: snapshot.points })), {
  nickname: state.nickname,
  points: 4321,
});

now += 1000;
const reset = service.resetSnapshot();
assert.equal(reset.lastEnergyAt, now);
assert.equal(reset.revision, 0);

const uiFiles = [
  'src/renewal/app.js',
  'src/renewal/minigame-controller.js',
  'src/renewal/worldboss-controller.js',
  'src/renewal/ranking-controller.js',
  'src/renewal/fx-controller.js',
];
uiFiles.forEach((file) => {
  const source = fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
  assert.equal(/\b(?:localStorage|Date\.now|Math\.random)\b/.test(source), false, `${file} bypasses runtime adapters`);
});
const appSource = fs.readFileSync(new URL('../src/renewal/app.js', import.meta.url), 'utf8');
assert.equal(/from ['"]\.\/storage\.js['"]/.test(appSource), false, 'app must not import the storage adapter directly');

console.log('renewal game service tests passed: local adapter, deterministic clock/RNG, named command boundary');
