-- 투기장 화면용 상태. 내 레이팅·등수·잔여 횟수·최근 전적과 상위 랭킹을 한 번에 준다.
-- 티어 라벨은 클라이언트가 ARENA_RULES 로 계산한다(등수까지 봐야 챌린저를 가릴 수 있다).
create or replace function public.gacha_s2_get_arena_state(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
  v_rules jsonb;
  v_attempts_per_hour integer;
  v_self public.gacha_s2_arena_players%rowtype;
  v_rating integer;
  v_rank integer;
  v_used integer;
begin
  select config->'arenaRules' into v_rules from public.gacha_s2_balance_versions where active;
  v_attempts_per_hour := coalesce((v_rules->>'attemptsPerHour')::integer, 3);

  select * into v_self from public.gacha_s2_arena_players where user_id = p_user_id;
  v_rating := coalesce(v_self.rating, coalesce((v_rules->>'startRating')::integer, 1000));
  v_rank := public.gacha_s2_arena_rank_of(p_user_id);
  v_used := public.gacha_s2_arena_attempts_used(p_user_id, v_now);

  return jsonb_build_object(
    'rating', v_rating,
    'rank', v_rank,
    'peakRating', coalesce(v_self.peak_rating, v_rating),
    'wins', coalesce(v_self.wins, 0),
    'losses', coalesce(v_self.losses, 0),
    'defendWins', coalesce(v_self.defend_wins, 0),
    'defendLosses', coalesce(v_self.defend_losses, 0),
    'weekAttacks', case when v_self.week_key = public.gacha_s2_arena_week_key(v_now)
      then coalesce(v_self.week_attacks, 0) else 0 end,
    'attemptsUsed', v_used,
    'attemptsPerHour', v_attempts_per_hour,
    'attemptsResetAt', floor(extract(epoch from (date_trunc('hour', v_now) + interval '1 hour')) * 1000)::bigint,
    'population', (select count(*) from public.gacha_s2_arena_players),
    'weekKey', public.gacha_s2_arena_week_key(v_now),
    -- 상위 100명. 랭킹 모달에서 보여준다.
    'ranking', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', ranked.rank, 'nickname', ranked.nickname, 'rating', ranked.rating,
        'wins', ranked.wins, 'losses', ranked.losses, 'isSelf', ranked.user_id = p_user_id
      ) order by ranked.rank)
      from (
        select a.user_id, acc.nickname, a.rating, a.wins, a.losses,
               row_number() over (order by a.rating desc, a.user_id) as rank
        from public.gacha_s2_arena_players a
        join public.gacha_s2_accounts acc on acc.id = a.user_id
        order by a.rating desc, a.user_id
        limit 100
      ) ranked
    ), '[]'::jsonb),
    -- 최근 전적. 내가 공격한 판과 당한 판을 함께 보여준다.
    'recentMatches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'matchId', recent.match_id,
        'role', recent.role,
        'won', recent.won,
        'reason', recent.reason,
        'opponent', recent.opponent,
        'ratingDelta', recent.rating_delta,
        'at', floor(extract(epoch from recent.resolved_at) * 1000)::bigint
      ) order by recent.resolved_at desc)
      from (
        select m.match_id, 'attack' as role, m.attacker_won as won, m.reason,
               acc.nickname as opponent,
               m.attacker_rating_after - m.attacker_rating_before as rating_delta,
               m.resolved_at
        from public.gacha_s2_arena_matches m
        join public.gacha_s2_accounts acc on acc.id = m.defender_id
        where m.attacker_id = p_user_id and m.status = 'resolved'
        union all
        select m.match_id, 'defend', not m.attacker_won, m.reason,
               acc.nickname,
               m.defender_rating_after - m.defender_rating_before,
               m.resolved_at
        from public.gacha_s2_arena_matches m
        join public.gacha_s2_accounts acc on acc.id = m.attacker_id
        where m.defender_id = p_user_id and m.status = 'resolved'
        order by resolved_at desc
        limit 20
      ) recent
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.gacha_s2_get_arena_state(uuid) from public, anon;
grant execute on function public.gacha_s2_get_arena_state(uuid) to service_role, authenticated;
