-- 투기장 운영 수치를 밸런스 설정에 싣는다. 서버 RPC 가 여기서 읽으므로
-- 횟수·행동력·ELO·보상을 코드 배포 없이 조정할 수 있다.
update public.gacha_s2_balance_versions
set config = jsonb_set(config, '{arenaRules}', jsonb_build_object(
  'startRating', 1000,
  'minRating', 800,
  'eloK', 24,
  'defenderDeltaScale', 0.8,
  'energyCost', 5,
  'attemptsPerHour', 3,
  'battleDuration', 60,
  'matchRatingBands', jsonb_build_array(100, 200, 400),
  'challengerSlots', 5,
  'seasonResetDivisor', 2,
  'weeklyRewards', jsonb_build_array(
    jsonb_build_object('maxRank', 3, 'points', 300000),
    jsonb_build_object('maxRank', 30, 'points', 200000),
    jsonb_build_object('maxRank', 100, 'points', 100000),
    jsonb_build_object('maxRank', null, 'points', 50000)
  )
), true)
where active;

-- 주간 정산. 월요일 00:00 KST 기준으로 지난 주를 마감한다.
-- 그 주에 공격을 한 번이라도 한 사람만 대상이며, 정산 후 레이팅을 시작점 쪽으로 절반 당긴다.
create or replace function public.gacha_s2_arena_settle_week(p_week_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_week text := coalesce(p_week_key, public.gacha_s2_arena_week_key(now() - interval '1 day'));
  v_config jsonb;
  v_rules jsonb;
  v_brackets jsonb;
  v_divisor numeric;
  v_min_rating integer;
  v_start integer;
  v_row record;
  v_points integer;
  v_bracket jsonb;
  v_after integer;
  v_granted integer := 0;
  v_total bigint := 0;
begin
  perform pg_advisory_xact_lock(hashtext('gacha_s2_arena_settlement:' || v_week));

  if exists (select 1 from public.gacha_s2_arena_weekly_rewards where week_key = v_week) then
    return jsonb_build_object('ok', true, 'weekKey', v_week, 'alreadySettled', true, 'granted', 0);
  end if;

  select config into v_config from public.gacha_s2_balance_versions where active;
  v_rules := v_config->'arenaRules';
  v_brackets := v_rules->'weeklyRewards';
  v_divisor := coalesce((v_rules->>'seasonResetDivisor')::numeric, 2);
  v_min_rating := coalesce((v_rules->>'minRating')::integer, 800);
  v_start := coalesce((v_rules->>'startRating')::integer, 1000);

  for v_row in
    select a.user_id, a.rating, a.week_attacks,
           row_number() over (order by a.rating desc, a.user_id) as rank
    from public.gacha_s2_arena_players a
    where a.week_key = v_week and a.week_attacks > 0
    order by a.rating desc, a.user_id
  loop
    -- 등수 구간을 위에서부터 훑어 처음 걸리는 보상을 준다.
    v_points := 0;
    for v_bracket in select value from jsonb_array_elements(v_brackets) loop
      if v_bracket->>'maxRank' is null or v_row.rank <= (v_bracket->>'maxRank')::integer then
        v_points := (v_bracket->>'points')::integer;
        exit;
      end if;
    end loop;

    v_after := greatest(v_min_rating, round(v_start + (v_row.rating - v_start) / v_divisor)::integer);

    insert into public.gacha_s2_arena_weekly_rewards (
      week_key, user_id, rank, rating, attacks, points, rating_after_reset
    ) values (
      v_week, v_row.user_id, v_row.rank, v_row.rating, v_row.week_attacks, v_points, v_after
    );

    update public.gacha_s2_player_states
    set points = points + v_points, revision = revision + 1, updated_at = now()
    where user_id = v_row.user_id;

    update public.gacha_s2_arena_players
    set rating = v_after, week_attacks = 0, week_key = null, updated_at = now()
    where user_id = v_row.user_id;

    v_granted := v_granted + 1;
    v_total := v_total + v_points;
  end loop;

  -- 그 주에 안 뛴 사람도 다음 주 출발선을 맞춰야 상위권이 굳지 않는다.
  update public.gacha_s2_arena_players
  set rating = greatest(v_min_rating, round(v_start + (rating - v_start) / v_divisor)::integer),
      week_attacks = 0, week_key = null, updated_at = now()
  where week_key is distinct from null or week_attacks > 0;

  return jsonb_build_object('ok', true, 'weekKey', v_week, 'granted', v_granted, 'totalPoints', v_total);
end;
$$;

revoke all on function public.gacha_s2_arena_settle_week(text) from public, anon, authenticated;
grant execute on function public.gacha_s2_arena_settle_week(text) to service_role;

do $$
declare v_rules jsonb;
begin
  select config->'arenaRules' into v_rules from public.gacha_s2_balance_versions where active;
  if v_rules is null then raise exception 'arenaRules missing'; end if;
  if (v_rules->>'attemptsPerHour')::integer <> 3 then raise exception 'attemptsPerHour wrong'; end if;
  if (v_rules->>'energyCost')::integer <> 5 then raise exception 'energyCost wrong'; end if;
  if jsonb_array_length(v_rules->'weeklyRewards') <> 4 then raise exception 'weeklyRewards wrong'; end if;
end;
$$;
