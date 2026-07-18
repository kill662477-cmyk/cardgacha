import assert from 'node:assert/strict';
import { GAME_COMMAND_TYPES, createGameSuccess } from '../src/renewal/service-contract.js';
import {
  SUPABASE_GAME_SERVICE_METHODS,
  createSupabaseGameService,
} from '../src/renewal/supabase-game-service.js';

const calls = [];
let now = 1000;
let token = 'user-session-jwt';
const snapshot = { revision: 7, nickname: 'MSTZ' };
const fetchImpl = async (url, options) => {
  const body = JSON.parse(options.body);
  calls.push({ url, options, body });
  if (body.kind === 'snapshot') {
    return new Response(JSON.stringify({ ok: true, serverTime: now, snapshot }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  const response = createGameSuccess({
    command: body.command,
    revision: 8,
    serverTime: now,
    serverSeed: 123,
    snapshot: { ...snapshot, revision: 8 },
    result: { formation: body.command.payload.formation },
  });
  return new Response(JSON.stringify(response), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};

const service = createSupabaseGameService({
  projectUrl: 'https://project.supabase.co',
  publishableKey: 'sb_publishable_browser_safe',
  getAccessToken: async () => token,
  fetch: fetchImpl,
  clock: { now: () => now++ },
  createIdempotencyKey: () => 'formation-command-001',
});
SUPABASE_GAME_SERVICE_METHODS.forEach((method) => assert.equal(typeof service[method], 'function'));

const loaded = await service.loadSnapshot();
assert.equal(loaded.snapshot.nickname, 'MSTZ');
const commandResponse = await service.sendCommand(
  GAME_COMMAND_TYPES.UPDATE_FORMATION,
  { formation: ['a', 'b', 'c', 'd', 'e'] },
  7,
);
assert.equal(commandResponse.ok, true);
assert.equal(commandResponse.revision, 8);
assert.equal(calls[1].url, 'https://project.supabase.co/functions/v1/game-command');
assert.equal(calls[1].options.headers.Authorization, 'Bearer user-session-jwt');
assert.equal(calls[1].options.headers.apikey, 'sb_publishable_browser_safe');
assert.equal(calls[1].body.command.commandId, 'formation-command-001');
assert.equal(JSON.stringify(calls).includes('service_role'), false);

token = '';
const unauthenticated = await service.loadSnapshot();
assert.equal(unauthenticated.code, 'AUTH_REQUIRED');
assert.equal(calls.length, 2, 'missing session must not issue a request');

const mismatchedService = createSupabaseGameService({
  projectUrl: 'https://project.supabase.co',
  publishableKey: 'sb_publishable_browser_safe',
  getAccessToken: async () => 'user-session-jwt',
  fetch: async (_url, options) => {
    const body = JSON.parse(options.body);
    return Response.json(createGameSuccess({
      command: { ...body.command, commandId: 'another-command', idempotencyKey: 'another-command' },
      revision: 8,
      serverTime: 1000,
      serverSeed: 1,
      snapshot: { revision: 8 },
    }));
  },
  clock: { now: () => 1000 },
});
const mismatched = await mismatchedService.sendCommand(
  GAME_COMMAND_TYPES.UPDATE_FORMATION,
  { formation: ['a', 'b', 'c', 'd', 'e'] },
  7,
  'expected-command-001',
);
assert.equal(mismatched.code, 'INTERNAL_ERROR');

assert.throws(() => createSupabaseGameService({
  projectUrl: 'http://insecure.example.com',
  publishableKey: 'key',
  getAccessToken: async () => 'token',
}), /project URL/);

console.log('renewal Supabase game service tests passed: JWT, publishable key, command contract, auth failure');
