import assert from 'node:assert/strict';
import { GAME_ERROR_CODES } from '../src/renewal/service-contract.js';
import { executeCommandWithVersionRetry } from '../src/renewal/server-command-retry.js';

let revision = 3;
const snapshots = [];
const requests = [];
const responses = [
  {
    ok: false,
    code: GAME_ERROR_CODES.VERSION_CONFLICT,
    latestSnapshot: { revision: 4 },
  },
  {
    ok: true,
    snapshot: { revision: 5 },
    result: { rewardPoints: 500 },
  },
];

const recovered = await executeCommandWithVersionRetry({
  type: 'purchasePack',
  payload: { productId: 'generalPack', quantity: 1 },
  sendCommand: async (type, payload, expectedRevision) => {
    requests.push({ type, payload, expectedRevision });
    return responses.shift();
  },
  getRevision: () => revision,
  applySnapshot: (snapshot) => {
    snapshots.push(snapshot.revision);
    revision = snapshot.revision;
  },
});

assert.equal(recovered.ok, true);
assert.deepEqual(snapshots, [4, 5]);
assert.deepEqual(requests.map((request) => request.expectedRevision), [3, 4]);
assert.equal(requests.length, 2, 'only one conflict recovery retry is allowed');

let noRetryCalls = 0;
const conflict = await executeCommandWithVersionRetry({
  type: 'updateFormation',
  payload: {},
  retryOnVersionConflict: false,
  sendCommand: async () => {
    noRetryCalls += 1;
    return { ok: false, code: GAME_ERROR_CODES.VERSION_CONFLICT, latestSnapshot: { revision: 6 } };
  },
  getRevision: () => 5,
  applySnapshot: () => {},
});
assert.equal(conflict.code, GAME_ERROR_CODES.VERSION_CONFLICT);
assert.equal(noRetryCalls, 1, 'explicit opt-out must preserve the conflict prompt');

let persistentCalls = 0;
const persistent = await executeCommandWithVersionRetry({
  type: 'attackWorldBoss',
  payload: { eventId: 'noise-zero-20260723-17' },
  sendCommand: async () => {
    persistentCalls += 1;
    return {
      ok: false,
      code: GAME_ERROR_CODES.VERSION_CONFLICT,
      latestSnapshot: { revision: 10 + persistentCalls },
    };
  },
  getRevision: () => revision,
  applySnapshot: (snapshot) => { revision = snapshot.revision; },
});
assert.equal(persistent.code, GAME_ERROR_CODES.VERSION_CONFLICT);
assert.equal(persistentCalls, 2, 'persistent conflicts must stop after one replay');

console.log('renewal server command retry tests passed: global snapshot sync, one safe replay, bounded conflict handling');
