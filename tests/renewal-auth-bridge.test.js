import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createAuthSessionService } from '../src/renewal/auth-session-service.js';

const calls = [];
const signOutCalls = [];
const auth = {
  getSession: async () => ({ data: { session: null } }),
  signInAnonymously: async () => ({ data: { session: { access_token: 'anonymous-jwt' } }, error: null }),
  signOut: async (options) => { signOutCalls.push(options); return { error: null }; },
};
const service = createAuthSessionService({
  projectUrl: 'https://project.supabase.co',
  publishableKey: 'sb_publishable_test',
  auth,
  fetch: async (url, options) => {
    calls.push({ url, options });
    return { ok: true, json: async () => ({ ok: true, accountId: 'account-1', nickname: 'MSTZ' }) };
  },
});
const signedIn = await service.signInWithLoginKey('legacy-login-key-000001');
assert.equal(signedIn.ok, true);
assert.equal(signedIn.session.access_token, 'anonymous-jwt');
assert.equal(calls[0].options.headers.Authorization, 'Bearer anonymous-jwt');
assert.equal(JSON.parse(calls[0].options.body).loginKey, 'legacy-login-key-000001');
assert.equal((await service.signInWithLoginKey('short')).code, 'INVALID_CREDENTIALS');

// Phase 2: SOOP 숲 로그인 exchange 코드 바인딩 분기.
const soopSignedIn = await service.signInWithSoopExchange('soop-exchange-code-1234567890');
assert.equal(soopSignedIn.ok, true);
assert.equal(soopSignedIn.session.access_token, 'anonymous-jwt');
assert.equal(JSON.parse(calls[1].options.body).soopExchange, 'soop-exchange-code-1234567890');
assert.equal((await service.signInWithSoopExchange('short')).code, 'INVALID_CREDENTIALS');
assert.deepEqual(await service.signOut(), { ok: true });
assert.deepEqual(signOutCalls, [{ scope: 'local' }]);

const sql = (await readFile(new URL('../supabase/renewal_migration_008_auth_bridge.sql', import.meta.url), 'utf8')).replace(/\s+/g, ' ');
assert.match(sql, /add column if not exists auth_user_id uuid unique references auth\.users\(id\) on delete set null/);
assert.match(sql, /create or replace function public\.gacha_s2_bind_auth_session\(/);
assert.match(sql, /create or replace function public\.gacha_s2_resolve_auth_account\(/);
assert.match(sql, /login_key_hash = p_login_key_hash/);
assert.match(sql, /attempts = least\(8, v_attempts\)/);
assert.match(sql, /interval '15 minutes'/);
assert.doesNotMatch(sql, /grant execute .* to authenticated/);

const edge = await readFile(new URL('../supabase/functions/session-exchange/index.ts', import.meta.url), 'utf8');
assert.match(edge, /supabase\.auth\.getUser\(jwt\)/);
assert.match(edge, /AUTH_RATE_LIMIT_PEPPER/);
assert.match(edge, /sha256\(loginKey\)/);
assert.match(edge, /hmac\(clientAddress, pepper\)/);
assert.match(edge, /gacha_s2_bind_soop_session/);
assert.doesNotMatch(edge, /console\.log|loginKey.*Deno\.env/);

console.log('renewal auth bridge tests passed: anonymous session, hashed legacy key, IP-HMAC rate limit');
