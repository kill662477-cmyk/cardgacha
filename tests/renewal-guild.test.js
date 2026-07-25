import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { GAME_COMMAND_TYPES } from '../src/renewal/service-contract.js';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const squash = (sql) => sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();

const schema = squash(await read('supabase/migrations/20260725000092_guild_m1_schema.sql'));
const query = squash(await read('supabase/migrations/20260725000093_guild_m1_query.sql'));
const owner = squash(await read('supabase/migrations/20260725000094_guild_m1_rpc_owner.sql'));
const join = squash(await read('supabase/migrations/20260725000095_guild_m1_rpc_join.sql'));
const member = squash(await read('supabase/migrations/20260725000096_guild_m1_rpc_member.sql'));
const router = await read('src/renewal/server-command-router.js');
const edge = await read('supabase/functions/game-command/index.ts');

// --- 스키마: 테이블·접근 통제 ---
const tables = [
  'gacha_s2_guild_emblems',
  'gacha_s2_guilds',
  'gacha_s2_guild_members',
  'gacha_s2_guild_join_requests',
  'gacha_s2_guild_leave_penalties',
];
for (const table of tables) {
  assert.match(schema, new RegExp(`create table if not exists public\\.${table}`), `${table} 생성 누락`);
  assert.match(schema, new RegExp(`alter table public\\.${table} enable row level security`), `${table} RLS 누락`);
  assert.match(schema, new RegExp(`revoke all on table public\\.${table} from public, anon, authenticated`), `${table} 권한 회수 누락`);
}

// 해산한 길드의 이름·소유권을 재사용할 수 있어야 하므로 활성 길드에만 유일성을 건다.
assert.match(schema, /create unique index if not exists gacha_s2_guilds_owner_active_idx on public\.gacha_s2_guilds \(owner_user_id\) where disbanded_at is null/);
assert.match(schema, /create unique index if not exists gacha_s2_guilds_name_active_idx on public\.gacha_s2_guilds \(lower\(name\)\) where disbanded_at is null/);
// 1인 1길드.
assert.match(schema, /create unique index if not exists gacha_s2_guild_members_user_idx on public\.gacha_s2_guild_members \(user_id\)/);
// 엠블럼은 테이블 참조로 관리해 커스텀 추가 시 스키마 변경이 필요 없어야 한다.
assert.match(schema, /emblem text not null default 'shield' references public\.gacha_s2_guild_emblems\(emblem_key\)/);
assert.equal((schema.match(/\('shield'|\('bolt'|\('star'|\('crown'|\('flame'|\('blade'|\('hexcore'|\('signal'/g) ?? []).length, 8, '기본 엠블럼 8종');
assert.match(schema, /join_mode text not null default 'approval' check \(join_mode in \('approval', 'auto'\)\)/);
assert.match(schema, /member_limit integer not null default 30/);

// --- 회귀 방지: 길드 명령은 반드시 revision 을 1 올려야 한다 ---
// gacha_s2_command_audit 에 CHECK (committed_revision = expected_revision + 1) 이 있어,
// 올리지 않으면 감사 로그 삽입이 실패해 모든 길드 명령이 거부된다.
assert.match(owner, /update public\.gacha_s2_player_states set revision = revision \+ 1, updated_at = now\(\) where user_id = p_user_id returning revision into v_revision/,
  '길드 공통 응답 헬퍼가 revision 을 1 올리지 않는다 (감사 로그 제약 위반)');
assert.match(owner, /values \( p_user_id, p_idempotency_key, p_command_type, p_request_hash, p_expected_revision, v_revision \)/,
  '감사 로그가 expected/committed revision 을 각각 기록해야 한다');

// --- 소유자 명령 ---
assert.match(owner, /select is_streamer into v_is_streamer/, '길드 생성은 방송인만 가능해야 한다');
assert.match(owner, /길드는 방송인 계정만 만들 수 있습니다/);
assert.match(owner, /where lower\(name\)=lower\(v_name\) and disbanded_at is null|where lower\(name\) = lower\(v_name\) and disbanded_at is null/, '이름 중복 검사');
// 해산 시 소속 행을 지우지 않으면 user_id 유일 인덱스 때문에 잔여 길드원이 다른 길드에 가입할 수 없다.
assert.match(owner, /delete from public\.gacha_s2_guild_members where guild_id = v_guild_id/, '해산 시 소속 행 삭제 누락');
assert.match(owner, /길드장만 해산할 수 있습니다/);
// 엠블럼·가입 방식은 길드장 전용, 공지는 부길드장도 가능.
assert.match(owner, /엠블럼과 가입 방식은 길드장만 변경할 수 있습니다/);

// --- 가입 명령 ---
assert.match(join, /길드 탈퇴 후 3일 동안은 다시 가입할 수 없습니다/, '페널티 기간 가입 차단');
assert.match(join, /if v_member_count >= v_guild\.member_limit then/, '정원 검사');
assert.match(join, /가입 신청은 최대 3개까지 가능합니다/, '동시 신청 3개 제한');
assert.match(join, /if v_guild\.join_mode = 'auto' then/, '자동 승인 모드 분기');
assert.match(join, /가입 신청을 처리할 권한이 없습니다/);
assert.match(join, /이미 다른 길드에 가입한 유저입니다/, '승인 시점 재검사');
assert.match(join, /탈퇴 페널티가 남아 있어 가입시킬 수 없습니다/, '승인 시점 페널티 재검사');

// --- 멤버 명령 ---
assert.match(member, /penalty_until = now\(\) \+ interval '3 days'/, '탈퇴·추방 페널티 3일');
assert.match(member, /길드장은 탈퇴할 수 없습니다\. 길드를 해산해 주세요\./);
assert.match(member, /길드장은 추방할 수 없습니다/);
assert.match(member, /부길드장은 길드장만 추방할 수 있습니다/);
assert.match(member, /부길드장은 최대 2명까지 임명할 수 있습니다/);
assert.match(member, /자기 자신을 추방할 수 없습니다/);
assert.match(member, /'leave'\)|'kick'\)/, '페널티 사유 기록');

// --- 조회 RPC ---
assert.match(query, /create or replace function public\.gacha_s2_get_guild_state/);
assert.match(query, /create or replace function public\.gacha_s2_list_guilds/);
assert.match(query, /create or replace function public\.gacha_s2_list_guild_emblems/);
// 기여도 판단 근거이므로 멤버 목록은 길드원 전원에게 공개한다(PDB-16 2.6).
assert.match(query, /'weeklygp', m\.weekly_gp/);
assert.match(query, /'joinedat', floor\(extract\(epoch from m\.joined_at\)/, '가입일 노출(신규 가입자 오판 방지)');
assert.match(query, /'lastcontributedat'/, '마지막 활동일 노출');
// 가입 신청 목록은 승인 권한자에게만 노출.
assert.match(query, /'joinrequests', case when v_can_manage then/);

// 조회 RPC 는 기존 스냅샷 경로를 건드리지 않아야 한다(회귀 위험 차단).
for (const sql of [schema, query, owner, join, member]) {
  assert.doesNotMatch(sql, /create or replace function public\.gacha_s2_get_player_snapshot/,
    '길드 마이그레이션이 기존 스냅샷 함수를 재정의하면 안 된다');
}

// --- 명령 계약 ↔ 라우터 정합성 ---
const guildCommands = {
  [GAME_COMMAND_TYPES.CREATE_GUILD]: 'gacha_s2_create_guild',
  [GAME_COMMAND_TYPES.DISBAND_GUILD]: 'gacha_s2_disband_guild',
  [GAME_COMMAND_TYPES.UPDATE_GUILD_SETTINGS]: 'gacha_s2_update_guild_settings',
  [GAME_COMMAND_TYPES.REQUEST_JOIN_GUILD]: 'gacha_s2_request_join_guild',
  [GAME_COMMAND_TYPES.CANCEL_JOIN_REQUEST]: 'gacha_s2_cancel_join_request',
  [GAME_COMMAND_TYPES.RESOLVE_JOIN_REQUEST]: 'gacha_s2_resolve_join_request',
  [GAME_COMMAND_TYPES.LEAVE_GUILD]: 'gacha_s2_leave_guild',
  [GAME_COMMAND_TYPES.KICK_GUILD_MEMBER]: 'gacha_s2_kick_guild_member',
  [GAME_COMMAND_TYPES.SET_GUILD_MEMBER_ROLE]: 'gacha_s2_set_guild_member_role',
};
const allSql = [owner, join, member].join(' ');
for (const [type, rpc] of Object.entries(guildCommands)) {
  assert.ok(type, '명령 타입 누락');
  assert.match(router, new RegExp(`'${rpc}'`), `라우터에 ${rpc} 매핑 누락`);
  assert.match(allSql, new RegExp(`create or replace function public\\.${rpc}\\(`), `${rpc} 정의 누락`);
}

// 인자를 받는 명령은 directArgs 에서 변환돼야 한다.
assert.match(router, /case GAME_COMMAND_TYPES\.CREATE_GUILD:[\s\S]*?p_name: payload\.name/);
assert.match(router, /case GAME_COMMAND_TYPES\.REQUEST_JOIN_GUILD:[\s\S]*?p_guild_id: payload\.guildId/);
assert.match(router, /case GAME_COMMAND_TYPES\.RESOLVE_JOIN_REQUEST:[\s\S]*?p_target_user_id: payload\.targetUserId, p_approve: payload\.approve/);
assert.match(router, /case GAME_COMMAND_TYPES\.SET_GUILD_MEMBER_ROLE:[\s\S]*?p_role: payload\.role/);

// --- Edge 조회 경로 ---
assert.match(edge, /body\.kind === 'guildState'/, 'edge 에 길드 조회 kind 누락');
assert.match(edge, /gacha_s2_get_guild_state/);

console.log('renewal guild M1 tests passed: 5 tables, 9 commands, revision-bump guard, penalty/limit rules');
