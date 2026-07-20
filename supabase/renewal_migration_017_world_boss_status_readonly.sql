-- Card Gacha Season 2: make world boss status a read-only hot path.
--
-- gacha_s2_get_world_boss_status previously called gacha_s2_sync_world_boss_event,
-- which takes `FOR UPDATE` on the single current event row and UPDATEs it on every
-- call. Once the boss opened, every online tab polls status during the raid window,
-- so all those calls serialized on that one row lock -> 10s+ per status call, which
-- starved the DB and made unrelated requests (snapshot/initial load = "카드 데이터
-- 동기화 중") crawl.
--
-- Fix: status now reads the event WITHOUT a lock and computes live HP from elapsed
-- server damage (deterministic: max_hp - player_damage - elapsed*dps). It never
-- writes on the common path -- the event row is only created (lazy ensure) when the
-- current slot's row is missing. Attack/claim keep sync_world_boss_event, which
-- legitimately needs the write lock and runs far less often than status polls.

create or replace function public.gacha_s2_get_world_boss_status(
  p_user_id uuid,
  p_event_id text default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
  v_config jsonb;
  v_version text;
  v_schedule jsonb;
  v_event_id text;
  v_event public.gacha_s2_world_boss_events%rowtype;
  v_progress jsonb;
  v_participants integer := 0;
  v_rank integer := null;
  v_leaderboard jsonb := '[]'::jsonb;
  v_raid_seconds integer;
  v_battle_seconds integer;
  v_hp_ratio numeric;
  v_elapsed_seconds bigint;
  v_server_damage bigint;
  v_current_hp bigint;
begin
  if p_user_id is null then return null; end if;
  select version, config into v_version, v_config
  from public.gacha_s2_balance_versions
  where active;
  if v_config is null then
    raise exception 'active balance version not found';
  end if;
  -- Read-only schedule computation (STABLE, no writes).
  v_schedule := public.gacha_s2_world_boss_schedule(v_config, v_now);
  v_event_id := coalesce(p_event_id, v_schedule->'currentSlot'->>'eventId');
  if v_event_id is null then
    return jsonb_build_object(
      'serverTime', public.gacha_s2_now_ms(),
      'schedule', v_schedule,
      'event', null,
      'player', null,
      'leaderboard', '[]'::jsonb
    );
  end if;
  -- Only write (create the event row) when the current slot's row does not exist yet.
  if not exists (select 1 from public.gacha_s2_world_boss_events where event_id = v_event_id) then
    perform public.gacha_s2_ensure_world_boss_schedule(v_now);
  end if;
  select * into v_event
  from public.gacha_s2_world_boss_events
  where event_id = v_event_id;
  if v_event.event_id is null then
    return null;
  end if;
  -- Live HP from elapsed server damage; never persisted on this read path.
  v_elapsed_seconds := floor(greatest(
    0,
    least(
      extract(epoch from (v_event.raid_ends_at - v_event.starts_at)),
      extract(epoch from (v_now - v_event.starts_at))
    )
  ))::bigint;
  v_server_damage := least(v_event.max_hp, v_elapsed_seconds * v_event.server_damage_per_second);
  v_current_hp := greatest(0, v_event.max_hp - v_event.player_damage - v_server_damage);
  v_progress := public.gacha_s2_world_boss_progress(p_user_id, v_event_id);
  select count(*)::integer into v_participants
  from public.gacha_s2_world_boss_players
  where event_id = v_event_id and attempts > 0;
  if coalesce((v_progress->>'attempts')::integer, 0) > 0 then
    select 1 + count(*)::integer into v_rank
    from public.gacha_s2_world_boss_players
    where event_id = v_event_id
      and total_damage > (v_progress->>'totalDamage')::bigint;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank', ranked.rank,
    'nickname', ranked.nickname,
    'damage', ranked.total_damage
  ) order by ranked.rank), '[]'::jsonb) into v_leaderboard
  from (
    select (row_number() over (order by player.total_damage desc, player.updated_at, player.user_id))::integer as rank,
      account.nickname,
      player.total_damage
    from public.gacha_s2_world_boss_players player
    join public.gacha_s2_accounts account on account.id = player.user_id
    where player.event_id = v_event_id and player.attempts > 0
    order by player.total_damage desc, player.updated_at, player.user_id
    limit 10
  ) ranked;
  v_raid_seconds := (v_config->'worldBossRules'->>'raidDurationSeconds')::integer;
  v_battle_seconds := (v_config->'worldBossRules'->>'battleDuration')::integer;
  v_hp_ratio := v_current_hp::numeric / v_event.max_hp;
  return jsonb_build_object(
    'serverTime', public.gacha_s2_now_ms(),
    'schedule', v_schedule,
    'event', jsonb_build_object(
      'eventId', v_event.event_id,
      'startsAt', floor(extract(epoch from v_event.starts_at) * 1000)::bigint,
      'raidEndsAt', floor(extract(epoch from v_event.raid_ends_at) * 1000)::bigint,
      'endsAt', floor(extract(epoch from v_event.ends_at) * 1000)::bigint,
      'currentHp', v_current_hp,
      'maxHp', v_event.max_hp,
      'defeated', v_current_hp = 0,
      'resultsOpen', v_now >= v_event.raid_ends_at and v_now < v_event.ends_at,
      'active', v_now >= v_event.starts_at and v_now < v_event.raid_ends_at and v_current_hp > 0,
      'phase', case when v_hp_ratio > 0.66 then 1 when v_hp_ratio > 0.33 then 2 else 3 end,
      'participants', v_participants
    ),
    'player', v_progress || jsonb_build_object(
      'rank', v_rank,
      'canAttack', v_now >= v_event.starts_at
        and v_now + make_interval(secs => v_battle_seconds) < v_event.raid_ends_at
        and v_current_hp > 0
        and (v_progress->>'attempts')::integer < (v_config->'worldBossRules'->>'maxAttempts')::integer
    ),
    'leaderboard', v_leaderboard,
    'raidDurationSeconds', v_raid_seconds
  );
end;
$$;

revoke all on function public.gacha_s2_get_world_boss_status(uuid, text) from public, anon, authenticated;
