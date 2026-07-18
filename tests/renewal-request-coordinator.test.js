import assert from 'node:assert/strict';
import { createRequestCoordinator, REQUEST_PHASES } from '../src/renewal/request-coordinator.js';
import { GAME_ERROR_CODES, createGameError } from '../src/renewal/service-contract.js';

let now = 1000;
let online = true;
const transitions = [];
const coordinator = createRequestCoordinator({
  clock: { now: () => now++ },
  isOnline: () => online,
  onTransition: (state) => transitions.push(state),
});

let release;
let calls = 0;
const deferred = () => new Promise((resolve) => { release = resolve; });
const first = coordinator.run('purchasePack', () => { calls += 1; return deferred(); }, { buttonId: 'buy' });
const duplicate = coordinator.run('purchasePack', () => { calls += 1; return Promise.resolve(); });
assert.equal(first, duplicate, 'double click must share one pending request');
assert.equal(calls, 0, 'task begins in a microtask');
await Promise.resolve();
assert.equal(calls, 1);
assert.equal(coordinator.isPending('purchasePack'), true);
release({ ok: true, revision: 2 });
const success = await first;
assert.equal(success.ok, true);
assert.equal(coordinator.getState('purchasePack').phase, REQUEST_PHASES.SUCCESS);
assert.equal(coordinator.isPending('purchasePack'), false);

online = false;
const offline = await coordinator.run('enhanceCard', () => { throw new Error('must not run'); });
assert.equal(offline.code, GAME_ERROR_CODES.OFFLINE);
assert.equal(coordinator.getState('enhanceCard').phase, REQUEST_PHASES.OFFLINE);
assert.equal(coordinator.hasRetryableFailure(), true);

online = true;
const retried = await coordinator.retryLast();
assert.equal(retried.code, GAME_ERROR_CODES.INTERNAL_ERROR);
assert.equal(coordinator.getState('enhanceCard').phase, REQUEST_PHASES.ERROR);

const conflictResponse = createGameError({
  code: GAME_ERROR_CODES.VERSION_CONFLICT,
  message: 'conflict',
  serverTime: now,
  revision: 9,
  latestSnapshot: { revision: 9 },
});
await coordinator.run('updateFormation', () => conflictResponse);
assert.equal(coordinator.getState('updateFormation').phase, REQUEST_PHASES.CONFLICT);
assert.equal(coordinator.hasRetryableFailure(), false);

const authResponse = createGameError({ code: GAME_ERROR_CODES.AUTH_REQUIRED, message: 'login', serverTime: now });
await coordinator.run('claimReward', () => authResponse);
assert.equal(coordinator.getState('claimReward').phase, REQUEST_PHASES.AUTH);
assert.ok(transitions.some((state) => state.phase === REQUEST_PHASES.PENDING));

console.log('renewal request coordinator tests passed: double-click lock, retry, offline, auth, conflict');
