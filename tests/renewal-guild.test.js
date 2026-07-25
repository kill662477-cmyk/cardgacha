import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { GAME_COMMAND_TYPES, validateGameCommand } from '../src/renewal/service-contract.js';
import { GUILD_RULES, guildLevelFor } from '../src/renewal/config.js';
import { applyGuildBuff } from '../src/renewal/collection.js';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const squash = (sql) => sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();

const schema = squash(await read('supabase/migrations/20260725000092_guild_m1_schema.sql'));
const query = squash(await read('supabase/migrations/20260725000093_guild_m1_query.sql'));
const owner = squash(await read('supabase/migrations/20260725000094_guild_m1_rpc_owner.sql'));
const join = squash(await read('supabase/migrations/20260725000095_guild_m1_rpc_join.sql'));
const member = squash(await read('supabase/migrations/20260725000096_guild_m1_rpc_member.sql'));
const gpLevels = squash(await read('supabase/migrations/20260725000097_guild_m2_gp_levels.sql'));
const snapshotSql = squash(await read('supabase/migrations/20260725000098_guild_m2_snapshot_buff.sql'));
const weekly = squash(await read('supabase/migrations/20260725000099_guild_m3_weekly_goals.sql'));
const raidSchema = squash(await read('supabase/migrations/20260725000100_guild_m4_raid_schema.sql'));
const raidRpc = squash(await read('supabase/migrations/20260725000101_guild_m4_raid_rpc.sql'));
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

// ── M2: 공헌도·레벨·버프 ──────────────────────────────────
assert.equal(GUILD_RULES.levels.length, 10);
assert.equal(GUILD_RULES.levels[0].memberLimit, 30);
// 정원 확장은 레벨 2·3에 앞당겨 초기 성장 체감을 준다.
assert.equal(GUILD_RULES.levels[1].memberLimit, 40, '레벨2 정원 40');
assert.equal(GUILD_RULES.levels[2].memberLimit, 50, '레벨3 정원 50');
// 무소속 유저를 무력화하지 않도록 스탯 버프 상한을 +5% 로 묶는다.
for (const tier of GUILD_RULES.levels) {
  for (const key of ['atk', 'hp', 'def', 'points']) {
    assert.ok(tier[key] <= 0.05, `레벨 ${tier.level} 의 ${key} 버프가 5% 를 넘는다`);
  }
}
// 카드 EXP 버프는 채택하지 않았다(체감이 없어 스탯 버프로 대체).
assert.ok(GUILD_RULES.levels.every((tier) => !('cardExp' in tier)));
assert.equal(GUILD_RULES.leavePenaltyDays, 3);
assert.equal(GUILD_RULES.maxOfficers, 2);
assert.equal(GUILD_RULES.maxPendingRequests, 3);
assert.equal(guildLevelFor(0).level, 1);
assert.equal(guildLevelFor(2999).level, 1);
assert.equal(guildLevelFor(3000).level, 2);
assert.equal(guildLevelFor(120000).level, 10);
assert.equal(guildLevelFor(999999).level, 10, '최대 레벨을 넘지 않는다');

// 버프 합산은 도감 상한 적용 "뒤"에 더해져야 도감 보너스가 깎이지 않는다.
const baseBonus = { attack: 0.10, hp: 0.08, defense: 0.05, bossDamage: 0.02, idle: 0.03, combatTotal: 0.25 };
const buffed = applyGuildBuff(baseBonus, { atk: 0.04, hp: 0.04, def: 0.03, points: 0.03 });
assert.equal(buffed.attack, 0.14);
assert.equal(buffed.hp, 0.12);
assert.equal(buffed.defense, 0.08);
assert.equal(buffed.bossDamage, 0.02, 'bossDamage 는 길드 버프 대상이 아니다');
assert.equal(buffed.idle, 0.03, 'idle 은 길드 버프 대상이 아니다');
assert.equal(baseBonus.attack, 0.10, 'applyGuildBuff 는 원본을 변경하지 않는다');
// 무소속이면 계산 결과가 이전과 완전히 같아야 한다.
assert.equal(applyGuildBuff(baseBonus, { atk: 0, hp: 0, def: 0 }), baseBonus);
assert.equal(applyGuildBuff(baseBonus, null), baseBonus);

// GP 는 기존 RPC 를 고치지 않고 감사 로그 트리거로 적립한다(회귀 위험 차단).
assert.match(gpLevels, /create trigger gacha_s2_guild_gp_trigger after insert on public\.gacha_s2_command_audit/);
assert.match(gpLevels, /when 'finishadventurerun' then v_gp := 5/);
assert.match(gpLevels, /when 'attackworldboss' then v_gp := 10/);
assert.match(gpLevels, /v_cap constant integer := 200/, '하루 개인 적립 상한');
assert.match(gpLevels, /if v_today >= v_cap then return new; end if;/);
// 정원은 절대 줄지 않아야 한다(이미 가입한 길드원 보호).
assert.match(gpLevels, /member_limit = greatest\(coalesce\(v_limit, 30\), member_limit, v_members\)/);
assert.match(gpLevels, /create table if not exists public\.gacha_s2_guild_levels/);
assert.match(gpLevels, /create table if not exists public\.gacha_s2_guild_contributions/);
assert.match(gpLevels, /create or replace function public\.gacha_s2_guild_buff/);

// 스냅샷은 guildBuff 만 덧붙이고 기존 필드를 유지해야 한다.
assert.match(snapshotSql, /'guildbuff', public\.gacha_s2_guild_buff\(s\.user_id\)/);
for (const field of ['schemaversion', 'revision', 'points', 'cardcopies', 'collectionrecords',
  'supportitems', 'worldboss', 'formation', 'powerranking']) {
  assert.match(snapshotSql, new RegExp(`'${field}'`), `스냅샷에서 ${field} 가 사라졌다`);
}
// 서버와 클라이언트가 같은 합산 함수를 써야 전투 재현 검증이 어긋나지 않는다.
assert.match(router, /applyGuildBuff\(base, snapshot\.guildBuff\)/);
const appJs = await read('src/renewal/app.js');
assert.match(appJs, /applyGuildBuff\(currentCollectionBonuses\(\), state\.guildBuff\)/);


// 네비에 화면을 추가하면 showScreen 에서 그 화면을 토글해 줘야 한다.
// SCREEN_IDS 에만 넣고 토글을 빠뜨리면 탭은 눌리는데 화면이 비어 있다(실제로 겪음).
const appSource = await read('src/renewal/app.js');
// 화면 id 와 elements 키가 다른 경우가 있어(worldboss -> worldBossScreen) 쌍으로 적는다.
for (const [screen, element] of [
  ['adventure', 'adventureScreen'], ['enhance', 'enhanceScreen'], ['collection', 'collectionScreen'],
  ['worldboss', 'worldBossScreen'], ['minigame', 'minigameScreen'], ['ranking', 'rankingScreen'],
  ['guild', 'guildScreen'],
]) {
  assert.match(appSource, new RegExp(`elements\.${element}\.hidden = screen !== '${screen}'`),
    `showScreen 이 ${screen} 화면을 토글하지 않는다 — 탭을 눌러도 빈 화면이 된다`);
}
// shop/inventory 는 같은 화면을 공유하므로 shopFamily 로 처리한다.
assert.match(appSource, /elements\.shopScreen\.hidden = !shopFamily/);


// 명령 타입을 GAME_COMMAND_TYPES 에 추가하면 payload 계약(allowedFields + validatePayload
// switch)에도 반드시 등록해야 한다. 빠뜨리면 서버로 가기 전에 "지원하지 않는 명령"으로
// 거부된다 — 길드 생성이 실제로 이 이유로 막혔다.
for (const type of Object.values(GAME_COMMAND_TYPES)) {
  const result = validateGameCommand({
    contractVersion: 1,
    commandId: 'contract-guard-0001',
    idempotencyKey: 'contract-guard-0001',
    type,
    expectedRevision: 0,
    payload: {},
    clientSentAt: Date.now(),
  });
  const unsupported = result.issues.some(
    (issue) => issue.path === 'type' && issue.message === '지원하지 않는 명령',
  );
  assert.equal(unsupported, false,
    `${type} 이 payload 계약에 등록되지 않았다 — allowedFields 와 validatePayload 에 추가해야 한다`);
}

console.log('renewal guild M1 tests passed: 5 tables, 9 commands, revision-bump guard, penalty/limit rules');
// ── M3: 주간 공동목표 ─────────────────────────────────────
assert.equal(GUILD_RULES.weekly.rewardPoints, 80_000);
assert.equal(GUILD_RULES.weekly.memberContributionCap, 0.08, '개인 기여 상한 8%');
assert.equal(GUILD_RULES.weekly.memberBaseline, 30);
assert.equal(GUILD_RULES.weekly.goals.length, 3);
assert.deepEqual(GUILD_RULES.weekly.goals.map((g) => g.source), ['adventure', 'minigame', 'worldboss']);

// 주간 리셋은 cron 없이 week_start_kst 키로 갈린다(월요일 시작).
assert.match(weekly, /date_trunc\('week', \(p_now at time zone 'asia\/seoul'\)\)/);
// 진행도는 별도 저장 없이 기여 내역에서 집계하고, 개인 상한을 적용한 뒤 합산해야 한다.
assert.match(weekly, /sum\(least\(per_user\.actions, v_cap\)\)/,
  '개인별 상한 적용 후 합산이어야 소수 인원이 혼자 목표를 끝낼 수 없다');
assert.match(weekly, /v_cap := greatest\(1, ceil\(v_target \* 0\.08\)::integer\)/);
assert.match(weekly, /v_target := ceil\(v_goal\.per_member::numeric \* v_members\)::integer/, '목표치 인원 비례');
// 주간 경계: 해당 주 7일만 집계.
assert.match(weekly, /c\.day_kst >= v_week and c\.day_kst < v_week \+ 7/);
// GP 는 하루 상한을 받지만 수행 횟수(actions)는 상한과 무관하게 세야 한다.
assert.match(weekly, /add column if not exists actions integer not null default 0/);
assert.match(weekly, /actions = public\.gacha_s2_guild_contributions\.actions \+ 1/);
// 보상은 전원 지급이므로 개인별 수령 기록으로 중복을 막는다.
assert.match(weekly, /create table if not exists public\.gacha_s2_guild_weekly_claims/);
assert.match(weekly, /이번 주 보상을 이미 받았습니다/);
assert.match(weekly, /주간 목표를 아직 달성하지 못했습니다/);
assert.match(weekly, /v_points constant integer := 80000/);
assert.match(router, /'gacha_s2_claim_guild_weekly_reward'/);

// ── M4: 길드 레이드 ───────────────────────────────────────
assert.deepEqual(GUILD_RULES.raid.scheduleIsoDays, [3, 6], '수·토');
assert.equal(GUILD_RULES.raid.hourKst, 21);
assert.equal(GUILD_RULES.raid.maxAttempts, 3);
assert.equal(GUILD_RULES.raid.hpPerActiveMember, 21_000_000);
assert.equal(GUILD_RULES.raid.successPoints, 50_000);
assert.equal(GUILD_RULES.raid.failurePoints, 15_000);

// HP 는 참여자 수가 아니라 활동 길드원 수 기준이어야 다수 참여 유인이 생긴다.
assert.match(raidSchema, /greatest\(v_active, 1\)::bigint \* 21000000/);
assert.match(raidSchema, /last_contributed_at >= p_now - interval '7 days'/, '활동 길드원 7일 기준');
assert.match(raidSchema, /active_member_count integer not null/, 'HP 산정 근거 스냅샷');
// 보상 명단은 시작 시점 소속 전원. 처치 후 가입해 보상만 받는 것을 막는다.
assert.match(raidSchema, /insert into public\.gacha_s2_guild_raid_players \(raid_id, user_id\) select v_raid\.raid_id, m\.user_id/);
assert.match(raidSchema, /extract\(isodow from v_start\) in \(3, 6\)/, '수·토만');
assert.match(raidSchema, /unique \(guild_id, starts_at\)/, '회차 중복 생성 방지');

// 서버가 재현 검증한 딜만 받는다.
assert.match(raidRpc, /p_verification_digest !~ '\^\[0-9a-f\]\{64\}\$'/);
assert.match(raidRpc, /if v_player\.attempts >= 3 then/, '개인 3회 제한');
assert.match(raidRpc, /이번 회차 참여 대상이 아닙니다/, '회차 시작 후 가입자 차단');
// 성공 시 전원, 실패 시 참여자만.
assert.match(raidRpc, /if v_defeated then v_points := 50000; elsif v_player\.attempts > 0 then v_points := 15000;/);
assert.match(raidRpc, /레이드에 실패했고 참여 기록이 없어 받을 보상이 없습니다/);
assert.match(raidRpc, /이미 보상을 받았습니다/, '중복 수령 차단');
// 미참여자도 명단에 나와야 누가 빠졌는지 알 수 있다.
assert.match(raidRpc, /create or replace function public\.gacha_s2_get_guild_raid_status/);
assert.match(raidRpc, /'participants', coalesce\(\(/);
assert.match(router, /'gacha_s2_claim_guild_raid_reward'/);
assert.match(router, /gacha_s2_attack_guild_raid/);
assert.match(router, /simulateWorldBossAttempt\(context\.formation, context\.bonuses, attemptNumber, raidId\)/,
  '레이드 전투는 월드보스 시뮬레이션을 재사용한다');

console.log('renewal guild M4 tests passed: raid slots, active-member HP, roster snapshot, reward split');
console.log('renewal guild M3 tests passed: weekly goals, 8% member cap, week boundary, claim guard');
console.log('renewal guild M2 tests passed: 10 levels, GP trigger, daily cap, buff merge parity');
