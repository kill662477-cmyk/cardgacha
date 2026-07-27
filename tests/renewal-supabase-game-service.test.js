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
  if (body.kind === 'guildApplicantProfile') {
    return Response.json({
      ok: true,
      serverTime: now,
      profile: {
        ok: true,
        userId: body.targetUserId,
        nickname: '신청자',
        formation: [],
        registeredCardIds: [],
      },
    });
  }
  if (body.kind === 'lottoState') {
    return Response.json({
      ok: true,
      serverTime: now,
      state: {
        ok: true,
        round: { roundId: '20260727-1500', saleOpen: true },
        history: [],
        recentWinners: [],
      },
    });
  }
  if (body.kind === 'mailbox') {
    return Response.json({
      ok: true,
      serverTime: now,
      mailbox: {
        ok: true,
        unreadCount: 1,
        messages: [{
          id: '00000000-0000-4000-8000-000000000010',
          title: '보상 지급 완료',
          body: '50,000 포인트 지급',
          category: 'REWARD',
          points: 50000,
          createdAt: '2026-07-27T10:00:00.000Z',
          readAt: null,
        }],
      },
    });
  }
  if (body.kind === 'mailboxRead') {
    return Response.json({
      ok: true,
      serverTime: now,
      result: {
        ok: true,
        mailId: body.mailId,
        readAt: '2026-07-27T10:01:00.000Z',
        unreadCount: 0,
      },
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

const applicantUserId = '00000000-0000-4000-8000-000000000001';
const applicantProfile = await service.getGuildApplicantProfile(applicantUserId);
assert.equal(applicantProfile.nickname, '신청자');
assert.equal(calls[2].body.kind, 'guildApplicantProfile');
assert.equal(calls[2].body.targetUserId, applicantUserId);
const invalidApplicant = await service.getGuildApplicantProfile('not-a-uuid');
assert.equal(invalidApplicant.code, 'VALIDATION_FAILED');
assert.equal(calls.length, 3, 'invalid applicant ID must not issue a request');
const lottoState = await service.getLottoState();
assert.equal(lottoState.round.roundId, '20260727-1500');
assert.deepEqual(lottoState.history, []);
assert.equal(calls[3].body.kind, 'lottoState');
const mailbox = await service.getMailbox();
assert.equal(mailbox.unreadCount, 1);
assert.equal(mailbox.messages[0].points, 50000);
assert.equal(calls[4].body.kind, 'mailbox');
const mailId = '00000000-0000-4000-8000-000000000010';
const markedMail = await service.markMailboxRead(mailId);
assert.equal(markedMail.mailId, mailId);
assert.equal(markedMail.unreadCount, 0);
assert.equal(calls[5].body.kind, 'mailboxRead');
assert.equal(calls[5].body.mailId, mailId);
const invalidMail = await service.markMailboxRead('not-a-uuid');
assert.equal(invalidMail.code, 'VALIDATION_FAILED');
assert.equal(calls.length, 6, 'invalid mail ID must not issue a request');

token = '';
const unauthenticated = await service.loadSnapshot();
assert.equal(unauthenticated.code, 'AUTH_REQUIRED');
assert.equal(calls.length, 6, 'missing session must not issue a request');

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
