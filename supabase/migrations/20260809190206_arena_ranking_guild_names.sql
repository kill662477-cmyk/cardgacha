-- 투기장 랭킹에 현재 소속된 활성 길드명을 함께 반환한다.
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
    'ranking', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', ranked.rank,
        'nickname', ranked.nickname,
        'guildName', ranked.guild_name,
        'rating', ranked.rating,
        'wins', ranked.wins,
        'losses', ranked.losses,
        'isSelf', ranked.user_id = p_user_id
      ) order by ranked.rank)
      from (
        select
          arena_player.user_id,
          account.nickname,
          guild.name as guild_name,
          arena_player.rating,
          arena_player.wins,
          arena_player.losses,
          row_number() over (order by arena_player.rating desc, arena_player.user_id) as rank
        from public.gacha_s2_arena_players arena_player
        join public.gacha_s2_accounts account on account.id = arena_player.user_id
        left join public.gacha_s2_guild_members guild_member on guild_member.user_id = arena_player.user_id
        left join public.gacha_s2_guilds guild
          on guild.guild_id = guild_member.guild_id and guild.disbanded_at is null
        order by arena_player.rating desc, arena_player.user_id
        limit 100
      ) ranked
    ), '[]'::jsonb),
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
        select
          arena_match.match_id,
          'attack' as role,
          arena_match.attacker_won as won,
          arena_match.reason,
          account.nickname as opponent,
          arena_match.attacker_rating_after - arena_match.attacker_rating_before as rating_delta,
          arena_match.resolved_at
        from public.gacha_s2_arena_matches arena_match
        join public.gacha_s2_accounts account on account.id = arena_match.defender_id
        where arena_match.attacker_id = p_user_id and arena_match.status = 'resolved'
        union all
        select
          arena_match.match_id,
          'defend',
          not arena_match.attacker_won,
          arena_match.reason,
          account.nickname,
          arena_match.defender_rating_after - arena_match.defender_rating_before,
          arena_match.resolved_at
        from public.gacha_s2_arena_matches arena_match
        join public.gacha_s2_accounts account on account.id = arena_match.attacker_id
        where arena_match.defender_id = p_user_id and arena_match.status = 'resolved'
        order by resolved_at desc
        limit 20
      ) recent
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.gacha_s2_get_arena_state(uuid) from public, anon;
grant execute on function public.gacha_s2_get_arena_state(uuid) to service_role, authenticated;
