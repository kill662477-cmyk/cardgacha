// Phase 2: SOOP 숲 로그인(일반 유저) 복구 검증.
// soop-auth Edge Function의 OAuth 플로우 구조와 gacha_s2_bind_soop_session RPC의
// 매칭/신규 생성/exchange 소비 로직이 migration에 올바르게 선언됐는지 확인한다.
// (실제 SOOP OAuth 호출은 운영 자격증명이 있어야 하므로 여기서는 정적 검증만.)
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = (await readFile(new URL('../supabase/migrations/20260719000010_renewal_migration_010_soop_user_auth.sql', import.meta.url), 'utf8')).replace(/\s+/g, ' ');
const edge = await readFile(new URL('../supabase/functions/soop-auth/index.ts', import.meta.url), 'utf8');
const sessionEdge = await readFile(new URL('../supabase/functions/session-exchange/index.ts', import.meta.url), 'utf8');

// migration: 테이블 + 함수 선언. (괄호 앞 스페이스 허용)
assert.match(migration, /create table if not exists public\.gacha_s2_soop_auth_exchanges\s*\(/);
assert.match(migration, /exchange_hash text primary key check \(exchange_hash ~ '\^\[0-9a-f\]\{64\}\$'\)/);
assert.match(migration, /soop_id text not null check \(length\(soop_id\) between 1 and 100\)/);
assert.match(migration, /access_token_ciphertext text not null/);
assert.match(migration, /expires_at timestamptz not null/);
assert.match(migration, /consumed_at timestamptz/);
assert.match(migration, /create table if not exists public\.gacha_s2_soop_auth_rate_log\s*\(/);
assert.match(migration, /enable row level security/g);

// RPC: 교환 코드 -> soop_id 매칭/신규 생성 -> auth_user_id 바인딩.
assert.match(migration, /create or replace function public\.gacha_s2_bind_soop_session\s*\(/);
assert.match(migration, /p_auth_user_id uuid,\s*p_exchange_code text,\s*p_rate_key text/);
assert.match(migration, /where exchange_hash = encode\(digest\(p_exchange_code, 'sha256'\), 'hex'\)/);
assert.match(migration, /where soop_id = v_exchange\.soop_id\s+for update/);
// 신규 유저 자동 생성 경로: accounts + player_states 동시 INSERT.
assert.match(migration, /insert into public\.gacha_s2_accounts \(nickname, login_key_hash, soop_id, is_streamer\)/);
assert.match(migration, /public\.gacha_s2_soop_login_key_hash\(v_exchange\.soop_id\)/);
assert.match(migration, /insert into public\.gacha_s2_player_states \(user_id\)/);
// exchange 코드 단일 소비.
assert.match(migration, /set consumed_at = now\(\)\s+where exchange_hash = v_exchange\.exchange_hash and consumed_at is null/);
// 동일 auth_user_id 기존 바인딩 회수 (login_key RPC와 동일 정책).
assert.match(migration, /set auth_user_id = null, auth_bound_at = null, updated_at = now\(\)\s+where auth_user_id = p_auth_user_id and id <> v_account\.id/);
assert.match(migration, /'isNew', v_is_new/);
// service_role 전용 권한.
assert.match(migration, /grant execute on function public\.gacha_s2_bind_soop_session\(uuid, text, text, text\) to service_role/);
assert.doesNotMatch(migration, /grant execute .* to authenticated/);

// soop-auth Edge Function: 시즌1 OAuth 패턴 (state 없음).
assert.match(edge, /const AUTH_URL = 'https:\/\/openapi\.sooplive\.com\/auth\/code'/);
assert.match(edge, /\?client_id=\$\{encodeURIComponent\(clientId\)\}/); // state 없음
assert.match(edge, /action === 'start'/);
assert.match(edge, /action === 'callback'/);
assert.match(edge, /SOOP_CLIENT_ID/);
assert.match(edge, /SOOP_CLIENT_SECRET/);
assert.match(edge, /SOOP_REDIRECT_URI/);
assert.match(edge, /extractSoopLoginId/);
assert.match(edge, /pageRedirect\('soopauth', exchange\)/);
assert.match(edge, /pageRedirect\('soopautherr'/);
// access_token AES-GCM 암호화 저장 (2분 TTL).
assert.match(edge, /EXCHANGE_TTL_MS = 2 \* 60 \* 1000/);
assert.match(edge, /encryptToken\(accessToken\)/);
assert.match(edge, /from\('gacha_s2_soop_auth_exchanges'\)/);
// 시크릿 노출 없음.
assert.doesNotMatch(edge, /console\.log|Deno\.env\.get\('SOOP_CLIENT_SECRET'\)\s*\?\?\s*['"]/);

// session-exchange: soopExchange 분기가 loginKey 분기와 함께 존재.
assert.match(sessionEdge, /soopExchange/);
assert.match(sessionEdge, /gacha_s2_bind_soop_session/);
assert.match(sessionEdge, /p_exchange_code: soopExchange/);

console.log('renewal SOOP user-auth tests passed: OAuth callback, exchange table, soop_id matching, new account creation, single-use exchange, auth binding');
