
begin;

-- 1. 모든 유저 로그아웃 처리 (game-command 401 유도)
update public.gacha_s2_accounts set auth_user_id = null, auth_bound_at = null;

-- 2. 게임 플레이 기록 관련 모든 테이블 초기화
truncate table public.gacha_s2_collection_records cascade;
truncate table public.gacha_s2_command_audit cascade;
truncate table public.gacha_s2_pack_draws cascade;
truncate table public.gacha_s2_enhancement_results cascade;
truncate table public.gacha_s2_adventure_runs cascade;
truncate table public.gacha_s2_minigame_daily cascade;
truncate table public.gacha_s2_minigame_runs cascade;
truncate table public.gacha_s2_world_boss_players cascade;
truncate table public.gacha_s2_world_boss_attempts cascade;
truncate table public.gacha_s2_support_draws cascade;
truncate table public.gacha_s2_soop_donation_events cascade;
truncate table public.gacha_s2_auth_rate_limits cascade;
truncate table public.gacha_s2_soop_auth_exchanges cascade;
truncate table public.gacha_s2_soop_auth_rate_log cascade;

-- 3. 계정 정보(accounts)는 유지하되, 상태(player_states)는 새 게임 상태로 리셋
delete from public.gacha_s2_player_states;
insert into public.gacha_s2_player_states (user_id)
select id from public.gacha_s2_accounts;

commit;
