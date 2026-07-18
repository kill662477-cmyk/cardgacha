-- Card Gacha Season 2: final removal of the Season 1 database objects.
-- DO NOT run with migration 001. Run only after Season 2 API cutover and backup verification.
-- This file intentionally aborts unless both session confirmations are supplied:
--   set app.gacha_s2_api_cutover = 'SEASON2_API_ONLY';
--   set app.gacha_s2_confirm_drop = 'DROP_SEASON1_AFTER_VERIFIED_BACKUP';

begin;

do $$
declare
  v_batch public.gacha_s2_import_batches%rowtype;
  v_source_users integer;
  v_s2_accounts integer;
  v_source_bridges integer;
  v_s2_bridges integer;
begin
  if current_setting('app.gacha_s2_api_cutover', true) is distinct from 'SEASON2_API_ONLY' then
    raise exception 'Season 2 API cutover confirmation is missing';
  end if;
  if current_setting('app.gacha_s2_confirm_drop', true) is distinct from 'DROP_SEASON1_AFTER_VERIFIED_BACKUP' then
    raise exception 'verified backup and Season 1 drop confirmation is missing';
  end if;

  if to_regclass('public.gacha_users') is null
    or to_regclass('public.gacha_collection') is null
    or to_regclass('public.gacha_soop_bridge_keys') is null then
    raise exception 'Season 1 source tables are missing or already partially removed';
  end if;
  if to_regclass('public.gacha_s2_accounts') is null
    or to_regclass('public.gacha_s2_player_states') is null
    or to_regclass('public.gacha_s2_streamer_bridges') is null then
    raise exception 'Season 2 account or bridge tables are missing';
  end if;

  select * into v_batch
  from public.gacha_s2_import_batches
  order by imported_at desc
  limit 1;
  if not found then
    raise exception 'verified Season 2 import batch is missing';
  end if;

  select count(*) into v_source_users from public.gacha_users;
  select count(*) into v_s2_accounts from public.gacha_s2_accounts;
  select count(*) into v_source_bridges from public.gacha_soop_bridge_keys;
  select count(*) into v_s2_bridges from public.gacha_s2_streamer_bridges;

  if v_source_users <> v_batch.source_users then
    raise exception 'Season 1 user count changed after import: batch %, current %', v_batch.source_users, v_source_users;
  end if;
  if v_s2_accounts <> v_batch.retained_users then
    raise exception 'Season 2 account count mismatch: batch %, current %', v_batch.retained_users, v_s2_accounts;
  end if;
  if v_source_bridges <> v_batch.source_bridge_keys
    or v_s2_bridges <> v_batch.retained_bridge_keys
    or v_source_bridges <> v_s2_bridges then
    raise exception 'streamer bridge count mismatch: source %, Season 2 %, batch source %, batch retained %',
      v_source_bridges, v_s2_bridges, v_batch.source_bridge_keys, v_batch.retained_bridge_keys;
  end if;
  if (select count(*) from public.gacha_s2_player_states) <> v_s2_accounts then
    raise exception 'not every Season 2 account has player state';
  end if;
  if exists (
    select 1
    from public.gacha_soop_bridge_keys old_bridge
    left join public.gacha_s2_streamer_bridges new_bridge
      on new_bridge.soop_id = old_bridge.soop_id
      and new_bridge.key_hash = old_bridge.key_hash
      and new_bridge.active = old_bridge.active
      and new_bridge.legacy_created_at is not distinct from old_bridge.created_at
      and new_bridge.last_used_at is not distinct from old_bridge.last_used_at
    where new_bridge.user_id is null
  ) then
    raise exception 'Season 2 streamer bridge data differs from Season 1';
  end if;
  if exists (
    select 1
    from public.gacha_s2_accounts account
    left join public.gacha_users legacy on legacy.id = account.legacy_user_id
    where legacy.id is null
      or legacy.login_key_hash <> account.login_key_hash
      or trim(legacy.nickname) <> account.nickname
      or nullif(trim(legacy.soop_id), '') is distinct from account.soop_id
  ) then
    raise exception 'Season 2 account identity data differs from Season 1';
  end if;
end;
$$;

drop function if exists public.gacha_take_rate_limit(text, integer, integer);
drop function if exists public.gacha_open_pack(uuid, integer, integer, jsonb);
drop function if exists public.gacha_claim_attendance(uuid, date, date, integer, integer, integer);
drop function if exists public.gacha_dismantle(uuid, jsonb);
drop function if exists public.gacha_claim_reward(uuid, text, integer, integer);
drop function if exists public.gacha_fuse(uuid, jsonb, boolean, text, integer, integer);
drop function if exists public.gacha_get_ranking(uuid);
drop function if exists public.gacha_grant_all_points(integer);
drop function if exists public.gacha_apply_soop_donation(text, text, text, integer);
drop function if exists public.gacha_settle_prediction_event(text, text);

drop function if exists public.gacha_s2_preview_season1_import();
drop function if exists public.gacha_s2_import_season1_accounts(uuid, integer, integer);
drop function if exists public.gacha_s2_season1_rank_reward(integer);

drop table if exists public.gacha_prediction_votes;
drop table if exists public.gacha_prediction_events;
drop table if exists public.gacha_soop_donation_events;
drop table if exists public.gacha_soop_bridge_keys;
drop table if exists public.gacha_card_serials;
drop table if exists public.gacha_card_counters;
drop table if exists public.gacha_member_rewards;
drop table if exists public.gacha_announcements;
drop table if exists public.gacha_collection;
drop table if exists public.gacha_rate_limits;
drop table if exists public.gacha_season1_final_top50;
drop table if exists public.gacha_users;

commit;
