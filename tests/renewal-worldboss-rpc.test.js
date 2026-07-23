import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../supabase/renewal_migration_006_world_boss.sql', import.meta.url), 'utf8');
const tierSql = await readFile(new URL('../supabase/migrations/20260722000056_worldboss_slot_tiers_and_energy.sql', import.meta.url), 'utf8');
const escalationSql = await readFile(new URL('../supabase/migrations/20260722000060_worldboss_escalation_and_guard_rewards.sql', import.meta.url), 'utf8');
const contract = await readFile(new URL('../src/renewal/service-contract.js', import.meta.url), 'utf8');
const normalized = sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const section = (start, end) => normalized.slice(
  normalized.indexOf(`create or replace function public.${start}`),
  end ? normalized.indexOf(`create or replace function public.${end}`) : undefined,
);
const schedule = section('gacha_s2_world_boss_schedule', 'gacha_s2_ensure_world_boss_schedule');
const sync = section('gacha_s2_sync_world_boss_event', 'gacha_s2_world_boss_progress');
const status = section('gacha_s2_get_world_boss_status', 'gacha_s2_attack_world_boss');
const attack = section('gacha_s2_attack_world_boss', 'gacha_s2_claim_world_boss_reward');
const claim = section('gacha_s2_claim_world_boss_reward');

for (const table of ['gacha_s2_world_boss_events', 'gacha_s2_world_boss_players', 'gacha_s2_world_boss_attempts']) {
  assert.match(normalized, new RegExp(`create table if not exists public\\.${table}`));
  assert.match(normalized, new RegExp(`alter table public\\.${table} enable row level security`));
  assert.match(normalized, new RegExp(`revoke all on table public\\.${table} from public, anon, authenticated`));
}
assert.match(normalized, /references public\.gacha_s2_balance_versions\(version\)/);
assert.doesNotMatch(normalized, /references public\.gacha_s2_balance_versions\(balance_version\)/);
assert.match(normalized, /unique \(event_id, user_id, attempt_number\)/);
assert.match(normalized, /unique \(user_id, command_id\)/);
assert.match(normalized, /create policy gacha_s2_world_boss_events_read/);
assert.match(normalized, /grant select on table public\.gacha_s2_world_boss_events to authenticated/);
assert.match(normalized, /alter publication supabase_realtime add table public\.gacha_s2_world_boss_events/);
assert.doesNotMatch(normalized, /grant select on table public\.gacha_s2_world_boss_(?:players|attempts) to authenticated/);

assert.match(normalized, /alter column world_boss set default/);
assert.match(normalized, /"eventid":"standby"/);
assert.match(schedule, /timezone\('asia\/seoul', p_now\)/);
assert.match(schedule, /'noise-zero-' \|\| to_char\(v_slot_local, 'yyyymmdd-hh24'\)/);
assert.match(schedule, /'raiddurationseconds'/);
assert.match(schedule, /'eventdurationseconds'/);
assert.match(normalized, /create or replace function public\.gacha_s2_ensure_world_boss_schedule/);
assert.match(normalized, /on conflict \(event_id\) do nothing/);

assert.match(sync, /for update/);
assert.match(sync, /v_elapsed_seconds \* v_event\.server_damage_per_second/);
assert.match(sync, /v_event\.max_hp - v_event\.player_damage - v_server_damage/);
assert.match(normalized, /create or replace function public\.gacha_s2_tick_world_boss_events/);
assert.match(normalized, /perform public\.gacha_s2_sync_world_boss_event\(v_event_id, p_now\)/);

assert.match(status, /'currenthp', v_event\.current_hp/);
assert.match(status, /'resultsopen', v_now >= v_event\.raid_ends_at and v_now < v_event\.ends_at/);
assert.match(status, /count\(\*\)::integer into v_participants/);
assert.match(status, /row_number\(\) over \(order by player\.total_damage desc/);
assert.match(status, /'canattack'/);

assert.match(attack, /p_verified_damage bigint/);
assert.match(attack, /p_verification_digest text/);
assert.match(attack, /gacha_s2_formation_snapshot\(p_user_id\)/);
assert.match(attack, /v_now \+ make_interval\(secs => v_battle_seconds\) >= v_event\.raid_ends_at/);
assert.match(attack, /v_attempts >= \(v_config->'worldbossrules'->>'maxattempts'\)::integer/);
assert.match(attack, /set player_damage = player_damage \+ p_verified_damage/);
assert.match(attack, /current_hp = greatest\(0, current_hp - p_verified_damage\)/);
assert.match(attack, /insert into public\.gacha_s2_world_boss_attempts/);
assert.match(attack, /gacha_s2_grant_formation_exp/);
assert.match(attack, /revision = revision \+ 1/);

assert.doesNotMatch(claim, /p_tier|p_defeated|p_reward_points|p_bonus_item/);
assert.match(claim, /v_now < v_event\.raid_ends_at or v_now >= v_event\.ends_at/);
assert.match(claim, /if v_player\.claimed_at is not null then/);
assert.match(claim, /jsonb_array_elements\(v_config->'worldbossrules'->'rewardtiers'\) with ordinality/);
assert.match(claim, /when v_defeated then \(v_tier->>'points'\)::integer/);
assert.match(claim, /else \(v_tier->>'failurepoints'\)::integer/);
assert.match(claim, /gacha_s2_roll_world_boss_drop/);
assert.match(claim, /set points = points \+ v_points/);

for (const command of [attack, claim]) {
  const replay = command.indexOf('select * into v_previous from public.gacha_s2_idempotency');
  const revision = command.indexOf('if p_expected_revision <> v_revision then');
  const commit = command.indexOf('insert into public.gacha_s2_idempotency');
  assert.ok(replay >= 0 && replay < revision, 'idempotency replay must precede revision conflict');
  assert.ok(revision < commit, 'revision validation must precede command commit');
}

const rpcSignatures = [
  'gacha_s2_get_world_boss_status\\(uuid, text\\)',
  'gacha_s2_tick_world_boss_events\\(timestamptz\\)',
  'gacha_s2_attack_world_boss\\(uuid, bigint, text, text, bigint, text\\)',
  'gacha_s2_claim_world_boss_reward\\(uuid, bigint, text, text\\)',
];
for (const fn of rpcSignatures) {
  assert.match(normalized, new RegExp(`grant execute on function public\\.${fn} to service_role`));
  assert.doesNotMatch(normalized, new RegExp(`grant execute on function public\\.${fn} to (?:anon|authenticated)`));
}

assert.match(contract, /\[GAME_COMMAND_TYPES\.ATTACK_WORLD_BOSS\]: \['eventId'\]/);
assert.match(contract, /\[GAME_COMMAND_TYPES\.CLAIM_WORLD_BOSS_REWARD\]: \['eventId'\]/);
assert.doesNotMatch(contract, /payload\.damage|payload\.verifiedDamage|payload\.tier/);

const normalizedTierSql = tierSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
assert.match(normalizedTierSql, /2026\.07\.22-worldboss-tiers-1/);
assert.match(normalizedTierSql, /'\{worldbossrules,attackenergycost\}'/);
assert.match(normalizedTierSql, /'\{worldbossrules,slottiers\}'/);
assert.match(normalizedTierSql, /v_tier := v_config->'worldbossrules'->'slottiers'->v_hour/);
assert.match(normalizedTierSql, /event\.starts_at > now\(\)/, 'only future untouched events may be retiered');
assert.match(normalizedTierSql, /action_energy = v_energy - v_energy_cost/);
assert.match(normalizedTierSql, /last_energy_at = v_now/);
assert.match(normalizedTierSql, /행동력이 부족합니다/);

const normalizedEscalationSql = escalationSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
assert.match(normalizedEscalationSql, /2026\.07\.22-worldboss-escalation-1/);
assert.match(normalizedEscalationSql, /"difficultymultiplier":1\.5/);
assert.match(normalizedEscalationSql, /"difficultymultiplier":2\.25/);
assert.match(normalizedEscalationSql, /"difficultymultiplier":3\.375/);
assert.match(normalizedEscalationSql, /"cleardestructionguardrate":0\.05/);
assert.match(normalizedEscalationSql, /"cleardestructionguardrate":0\.20/);
assert.match(normalizedEscalationSql, /add column if not exists bonus_item_ids jsonb/);
assert.match(normalizedEscalationSql, /bonus_item_ids = v_bonus_item_ids/);
assert.match(normalizedEscalationSql, /gacha_s2_seed_roll\(v_seed, 30\) < v_guard_rate/);
assert.match(normalizedEscalationSql, /and not \(v_bonus_item_ids \? 'destructionguard'\)/, 'generic guard and clear guard must not duplicate');
assert.match(normalizedEscalationSql, /'bonusitemids', v_bonus_item_ids/);
assert.match(normalizedEscalationSql, /event\.starts_at > now\(\)/, 'only future untouched events may be retiered');

console.log('renewal world-boss RPC tests passed: KST slots, atomic shared HP, trusted attacks, result-window rewards');
