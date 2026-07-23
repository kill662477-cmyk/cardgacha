import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../supabase/renewal_migration_005_adventure_and_minigames.sql', import.meta.url), 'utf8');
const rulePathFixSql = await readFile(new URL('../supabase/migrations/20260722000052_fix_minigame_global_rule_paths.sql', import.meta.url), 'utf8');
const legacyFinishFixSql = await readFile(new URL('../supabase/migrations/20260722000053_fix_legacy_minigame_finish_revision.sql', import.meta.url), 'utf8');
const highScoreRewardFixSql = await readFile(new URL('../supabase/migrations/20260722000054_fix_sumten_high_score_reward_constraint.sql', import.meta.url), 'utf8');
const ladderSql = await readFile(new URL('../supabase/migrations/20260722000057_ladder_minigame.sql', import.meta.url), 'utf8');
const dailyCapSql = await readFile(new URL('../supabase/migrations/20260722000059_enforce_minigame_daily_cap.sql', import.meta.url), 'utf8');
const hardAdventureSql = await readFile(new URL('../supabase/migrations/20260723000077_hard_adventure.sql', import.meta.url), 'utf8');
const contract = await readFile(new URL('../src/renewal/service-contract.js', import.meta.url), 'utf8');
const normalizedLadder = ladderSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const normalizedDailyCap = dailyCapSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const normalizedHardAdventure = hardAdventureSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const normalized = sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const section = (start, end) => normalized.slice(
  normalized.indexOf(`create or replace function public.${start}`),
  end ? normalized.indexOf(`create or replace function public.${end}`) : undefined,
);
const startAdventure = section('gacha_s2_start_adventure_run', 'gacha_s2_finish_adventure_run');
const finishAdventure = section('gacha_s2_finish_adventure_run', 'gacha_s2_claim_quick_battle');
const startMinigame = section('gacha_s2_start_minigame', 'gacha_s2_finish_minigame');
const finishMinigame = section('gacha_s2_finish_minigame');

// gacha_s2_claim_quick_battle was superseded by migration 013 (4h rolling window instead of a
// calendar-day reset) -- read the currently-active body from there, not the original in 005.
const quickBattleSql = await readFile(new URL('../supabase/renewal_migration_013_quick_battle_4h_window.sql', import.meta.url), 'utf8');
const quickBattle = quickBattleSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();

for (const table of ['gacha_s2_adventure_runs', 'gacha_s2_minigame_daily', 'gacha_s2_minigame_runs']) {
  assert.match(normalized, new RegExp(`create table if not exists public\\.${table}`));
  assert.match(normalized, new RegExp(`alter table public\\.${table} enable row level security`));
  assert.match(normalized, new RegExp(`revoke all on table public\\.${table} from public, anon, authenticated`));
}
assert.match(normalized, /reward_points integer not null default 0 check \(reward_points between 0 and 3000\)/);
assert.match(normalized, /create unique index if not exists idx_gacha_s2_adventure_one_active.*where status = 'active'/);
assert.match(normalized, /create unique index if not exists idx_gacha_s2_minigame_one_active.*where status = 'active'/);
assert.match(normalized, /verification_digest text not null check \(verification_digest ~ '\^\[0-9a-fa-f\]\{64\}\$'\)/);
assert.match(normalized, /input_digest text check \(input_digest is null or input_digest ~ '\^\[0-9a-fa-f\]\{64\}\$'\)/);
assert.equal((normalized.match(/references public\.gacha_s2_balance_versions\(version\)/g) ?? []).length, 2);
assert.doesNotMatch(normalized, /references public\.gacha_s2_balance_versions\(balance_version\)/);
assert.doesNotMatch(normalized, /select balance_version, config|where balance_version = v_run\.balance_version/);
assert.match(normalized, /'adventurerun', s\.adventure_run \|\| coalesce/);
assert.match(normalized, /'verifiedclearedstages', run\.verified_cleared_stages/);
assert.match(normalized, /'minigameruns', coalesce/);
assert.match(normalized, /'board', run\.board/);
assert.match(startMinigame, /expires_at >= now\(\)/);
assert.match(startMinigame, /expires_at < now\(\)/);
assert.doesNotMatch(startMinigame, /expires_at \+ interval '15 seconds'/);
assert.match(finishMinigame, /v_run\.expires_at \+ interval '15 seconds'/);

assert.match(normalized, /create or replace function public\.gacha_s2_formation_snapshot/);
assert.match(normalized, /count\(\*\) = 5 and count\(distinct catalog\.card_id\) = 5/);
assert.match(normalized, /catalog\.rarity <> 'ex' and not catalog\.is_group/);
assert.match(normalized, /create or replace function public\.gacha_s2_roll_adventure_drop/);
assert.match(normalized, /'bonusdroprules'->'adventuretiers'/);
assert.match(normalized, /create or replace function public\.gacha_s2_grant_formation_exp/);
assert.match(normalized, /'exprequirements'->>\(owned\.enhancement\)/);
assert.match(normalized, /create or replace function public\.gacha_s2_grant_ex_milestones/);
assert.match(normalized, /insert into public\.gacha_s2_collection_records/);

assert.match(startAdventure, /p_verified_cleared_stages integer/);
assert.match(startAdventure, /p_verification_digest text/);
assert.match(startAdventure, /select revision, adventure_runs into v_revision, v_adventure_runs.*for update/);
assert.match(startAdventure, /public\.gacha_s2_formation_snapshot\(p_user_id\)/);
assert.match(startAdventure, /'runwindowms'/);
assert.match(startAdventure, /'maxrunsperwindow'/);
assert.match(startAdventure, /insert into public\.gacha_s2_adventure_runs/);
assert.match(startAdventure, /'runid', v_run_id::text/);
assert.match(startAdventure, /revision = revision \+ 1/);

assert.doesNotMatch(finishAdventure, /p_verified_cleared_stages|p_reward_points|p_card_exp/);
assert.match(finishAdventure, /v_run\.verified_cleared_stages/);
assert.match(finishAdventure, /'maxpointsperrun'/);
assert.match(finishAdventure, /gacha_s2_roll_adventure_drop/);
assert.match(finishAdventure, /gacha_s2_grant_ex_milestones/);
assert.match(finishAdventure, /gacha_s2_grant_formation_exp/);
assert.match(finishAdventure, /set points = points \+ v_points/);
assert.match(finishAdventure, /status = case when verified_cleared_stages = 50 then 'completed' else 'failed' end/);

assert.match(quickBattle, /p_verified_cleared_stages not between 1 and 50/);
assert.match(quickBattle, /'quickbattleenergy'/);
assert.match(quickBattle, /'quickbattledailylimit'/);
assert.match(quickBattle, /'runwindowms'/);
assert.match(quickBattle, /action_energy = v_energy -/);
assert.match(quickBattle, /quick_battle = jsonb_build_object\('windowstartedat', v_quick_window_started, 'count', v_quick_count \+ 1\)/);
assert.match(quickBattle, /adventure_runs = jsonb_build_object/);
assert.match(quickBattle, /insert into public\.gacha_s2_adventure_runs/);
// 4시간 롤링 윈도우로 초기화 (달력 날짜 기반 리셋 아님).
assert.match(quickBattle, /v_quick_window_started := greatest\(0, coalesce\(\(v_quick->>'windowstartedat'\)::bigint, 0\)\)/);
assert.match(quickBattle, /v_now_ms - v_quick_window_started >= v_quick_window_ms/);
assert.doesNotMatch(quickBattle, /v_quick->>'date'/, 'day-based reset must be fully replaced by the 4h window');

assert.match(normalized, /create or replace function public\.gacha_s2_memory_board/);
assert.match(normalized, /digest\(p_seed::text \|\| ':deck:' \|\| card_id/);
assert.match(normalized, /create or replace function public\.gacha_s2_sum_ten_board/);
assert.match(normalized, /generate_series\(0, 169\)/);
assert.match(normalized, /create or replace function public\.gacha_s2_verify_memory_log/);
assert.match(normalized, /p_board->>\(v_left\) = p_board->>\(v_right\)/);
assert.match(normalized, /v_score := v_score \+ 100 \+ v_streak \* 20/);
assert.match(normalized, /v_next_allowed_at := v_at_ms \+ 320/);
assert.match(normalized, /v_next_allowed_at := v_at_ms \+ 650/);
assert.match(normalized, /p_server_elapsed_ms \+ 1000/);
assert.match(normalized, /create or replace function public\.gacha_s2_verify_sum_ten_log/);
assert.match(normalized, /v_selected > 0 and v_sum = 10/);
assert.match(normalized, /v_score := v_score \+ v_selected/);

assert.match(startMinigame, /select revision, action_energy, max_action_energy, last_energy_at.*for update/);
assert.match(startMinigame, /dailypointcappergame/);
assert.match(startMinigame, /v_config->'minigamerules'->>'dailypointcappergame'/);
assert.match(startMinigame, /v_config->'minigamerules'->>'energycost'/);
assert.doesNotMatch(startMinigame, /v_config->'minigamerules'->p_game->>'(?:dailypointcappergame|energycost)'/);
assert.match(startMinigame, /energyrecoveryminutes/);
assert.match(startMinigame, /gacha_s2_memory_board\(v_seed, v_pairs\)/);
assert.match(startMinigame, /gacha_s2_sum_ten_board\(v_seed\)/);
assert.match(startMinigame, /action_energy = v_energy - v_energy_cost/);
assert.match(startMinigame, /insert into public\.gacha_s2_minigame_runs/);

assert.match(finishMinigame, /p_input_log jsonb/);
assert.match(finishMinigame, /gacha_s2_verify_memory_log/);
assert.match(finishMinigame, /gacha_s2_verify_sum_ten_log/);
assert.match(finishMinigame, /submitted score|제출 점수/);
assert.match(finishMinigame, /\(v_verified->>'score'\)::integer <> p_claimed_score/);
assert.match(finishMinigame, /v_input_digest := encode\(digest\(p_input_log::text, 'sha256'\), 'hex'\)/);
assert.match(finishMinigame, /v_reward := least\(greatest\(0, v_daily_cap - v_daily_points\), v_raw_reward\)/);
assert.match(finishMinigame, /v_config->'minigamerules'->>'dailypointcappergame'/);
assert.doesNotMatch(finishMinigame, /v_config->'minigamerules'->v_run\.game->>'dailypointcappergame'/);
assert.match(finishMinigame, /points_earned = points_earned \+ v_reward/);
assert.match(finishMinigame, /set points = points \+ v_reward/);
assert.doesNotMatch(finishMinigame, /p_reward|p_verified_score|p_completed|p_input_digest/);

const normalizedRulePathFix = rulePathFixSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
assert.match(normalizedRulePathFix, /gacha_s2_start_minigame\(uuid,bigint,text,text,text\)/);
assert.match(normalizedRulePathFix, /gacha_s2_finish_minigame\(uuid,bigint,text,uuid,jsonb,integer\)/);
assert.match(normalizedRulePathFix, /replace\( v_start_definition/);
assert.match(normalizedRulePathFix, /replace\( v_finish_definition/);
assert.match(normalizedRulePathFix, /expires_at >= now\(\)/);
assert.match(normalizedRulePathFix, /expires_at < now\(\)/);
assert.match(normalizedRulePathFix, /raise exception 'expected broken minigame start rule paths were not found'/);
assert.match(normalizedRulePathFix, /raise exception 'expected broken minigame finish rule path was not found'/);

const normalizedLegacyFinishFix = legacyFinishFixSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
assert.match(normalizedLegacyFinishFix, /gacha_s2_command_finish_minigame\(text,uuid,jsonb,integer\)/);
assert.match(normalizedLegacyFinishFix, /greatest\(coalesce\(v_expected_revision, 0\), 0\), null, null/);
assert.match(normalizedLegacyFinishFix, /raise exception 'stale minigame revision reference remains'/);

const normalizedHighScoreRewardFix = highScoreRewardFixSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
assert.match(normalizedHighScoreRewardFix, /drop constraint if exists gacha_s2_minigame_runs_reward_points_check/);
assert.match(normalizedHighScoreRewardFix, /check \(reward_points between 0 and 3000\)/);

assert.match(normalizedLadder, /create table if not exists public\.gacha_s2_ladder_plays/);
assert.match(normalizedLadder, /create or replace function public\.gacha_s2_play_ladder/);
assert.match(normalizedLadder, /p_lane is null or p_lane < 0 or p_lane > 5/);
assert.match(normalizedLadder, /v_reward_index := least\(5, floor\(public\.gacha_s2_seed_roll\(v_seed, 0\) \* 6\)::integer\)/);
assert.match(normalizedLadder, /action_energy = v_energy - v_energy_cost/);
assert.match(normalizedLadder, /set points_earned = public\.gacha_s2_minigame_daily\.points_earned \+ excluded\.points_earned/);
assert.match(normalizedLadder, /set points = points \+ v_reward/);
assert.match(normalizedLadder, /'rewardpoints', v_reward/);
assert.match(normalizedLadder, /revoke all on function public\.gacha_s2_play_ladder\(uuid, bigint, text, integer\) from public, anon, authenticated/);
assert.match(normalizedLadder, /grant execute on function public\.gacha_s2_play_ladder\(uuid, bigint, text, integer\) to service_role/);

assert.match(normalizedDailyCap, /check \(points_earned between 0 and 3000\)/);
assert.match(normalizedDailyCap, /set points_earned = least\(points_earned, 3000\)/);
assert.match(normalizedDailyCap, /v_daily_points >= v_daily_cap/);
assert.match(normalizedDailyCap, /v_reward := least\(v_daily_cap - v_daily_points, v_rolled_reward\)/);
assert.match(normalizedDailyCap, /'rolledrewardpoints', v_rolled_reward/);
assert.match(normalizedDailyCap, /'rewardpoints', v_reward/);
assert.match(normalizedDailyCap, /action_energy = v_energy - v_energy_cost/);
assert.ok(
  normalizedDailyCap.indexOf('if v_daily_points >= v_daily_cap then')
    < normalizedDailyCap.indexOf('action_energy = v_energy - v_energy_cost'),
  'daily cap rejection must happen before ladder energy is charged',
);
assert.match(normalizedDailyCap, /revoke all on function public\.gacha_s2_play_ladder\(uuid, bigint, text, integer\) from public, anon, authenticated/);
assert.match(normalizedDailyCap, /grant execute on function public\.gacha_s2_play_ladder\(uuid, bigint, text, integer\) to service_role/);

for (const command of [startAdventure, finishAdventure, quickBattle, startMinigame, finishMinigame]) {
  const replay = command.indexOf('select * into v_previous from public.gacha_s2_idempotency');
  const revision = command.indexOf('if p_expected_revision <> v_revision then');
  const commit = command.indexOf('insert into public.gacha_s2_idempotency');
  assert.ok(replay >= 0 && replay < revision, 'idempotency replay must precede revision conflict');
  assert.ok(revision < commit, 'revision validation must precede command commit');
}

const rpcSignatures = [
  'gacha_s2_start_adventure_run\\(uuid, bigint, text, integer, text\\)',
  'gacha_s2_finish_adventure_run\\(uuid, bigint, text, uuid\\)',
  'gacha_s2_claim_quick_battle\\(uuid, bigint, text, integer, text\\)',
  'gacha_s2_start_minigame\\(uuid, bigint, text, text, text\\)',
  'gacha_s2_finish_minigame\\(uuid, bigint, text, uuid, jsonb, integer\\)',
];
for (const fn of rpcSignatures) {
  assert.match(normalized, new RegExp(`revoke all on function public\\.${fn} from public, anon, authenticated`));
  assert.match(normalized, new RegExp(`grant execute on function public\\.${fn} to service_role`));
  assert.doesNotMatch(normalized, new RegExp(`grant execute on function public\\.${fn} to (?:anon|authenticated)`));
}

assert.match(contract, /START_ADVENTURE_RUN: 'startAdventureRun'/);
assert.match(contract, /CLAIM_QUICK_BATTLE: 'claimQuickBattle'/);
assert.match(contract, /FINISH_MINIGAME: 'finishMinigame'/);
assert.match(contract, /PLAY_LADDER: 'playLadder'/);
assert.match(contract, /payload\.inputLog/);
assert.doesNotMatch(contract, /payload\.inputDigest/);
assert.doesNotMatch(contract, /payload\.verifiedClearedStages|payload\.verificationDigest/);
assert.match(normalizedHardAdventure, /p_mode text/);
assert.match(normalizedHardAdventure, /p_mode = 'hard' and v_cleared_stage < 50/);
assert.match(normalizedHardAdventure, /"minpointsperrun":7000/);
assert.match(normalizedHardAdventure, /"maxpointsperrun":20000/);
assert.match(normalizedHardAdventure, /then 50 \+ p_verified_cleared_stages/);
assert.match(normalizedHardAdventure, /gacha_s2_start_adventure_run\(uuid, bigint, text, integer, text, text\)/);
assert.match(normalizedHardAdventure, /gacha_s2_claim_quick_battle\(uuid, bigint, text, integer, text, text\)/);
assert.match(contract, /\[GAME_COMMAND_TYPES\.CLAIM_QUICK_BATTLE\]: \['mode'\]/);

console.log('renewal adventure/minigame RPC tests passed: trusted battle verdict, atomic rewards, server boards, replayed input logs');
