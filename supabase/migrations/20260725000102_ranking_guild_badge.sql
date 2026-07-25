-- 랭킹 응답에 소속 길드(이름·태그·엠블럼)를 싣는다.
-- 랭커 편성 모달과 내 프로필에서 길드를 보여 주기 위해서다.
-- 무소속이면 guild 가 null 이라 기존 화면과 동일하게 동작한다.
create or replace function public.gacha_s2_get_power_ranking(
  p_user_id uuid,
  p_verified_power integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rank integer;
  v_population integer;
  v_top_fifty_power integer := 0;
  v_leaders jsonb := '[]'::jsonb;
  v_nickname text;
  v_guild jsonb;
begin
  if p_user_id is null or p_verified_power is null or p_verified_power < 0 or p_verified_power > 2000000000 then
    raise exception 'invalid power ranking input';
  end if;

  update public.gacha_s2_player_states
  set power_snapshot = p_verified_power,
      power_snapshot_at = now()
  where user_id = p_user_id;
  if not found then raise exception 'Season 2 account state not found'; end if;

  select nickname into v_nickname
  from public.gacha_s2_accounts
  where id = p_user_id;

  select case when g.guild_id is null then null else jsonb_build_object(
    'name', g.name, 'tag', g.tag, 'emblem', g.emblem, 'level', g.level
  ) end into v_guild
  from public.gacha_s2_guild_members m
  join public.gacha_s2_guilds g on g.guild_id = m.guild_id and g.disbanded_at is null
  where m.user_id = p_user_id;

  with ranked as (
    select state.user_id,
      account.nickname,
      state.power_snapshot,
      state.power_snapshot_at,
      coalesce(state.representative_card_id, state.formation[1]) as representative_card_id,
      state.formation,
      guild.name as guild_name,
      guild.tag as guild_tag,
      guild.emblem as guild_emblem,
      guild.level as guild_level,
      row_number() over (
        order by state.power_snapshot desc, state.power_snapshot_at asc nulls last, state.user_id
      )::integer as rank
    from public.gacha_s2_player_states state
    join public.gacha_s2_accounts account on account.id = state.user_id
    left join public.gacha_s2_guild_members member on member.user_id = state.user_id
    left join public.gacha_s2_guilds guild
      on guild.guild_id = member.guild_id and guild.disbanded_at is null
  )
  select
    (select count(*)::integer from ranked),
    (select rank from ranked where user_id = p_user_id),
    coalesce((select power_snapshot from ranked where rank = 50), 0),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', ranked.rank,
        'nickname', ranked.nickname,
        'power', ranked.power_snapshot,
        'representativeCardId', ranked.representative_card_id,
        'guild', case when ranked.guild_name is null then null else jsonb_build_object(
          'name', ranked.guild_name,
          'tag', ranked.guild_tag,
          'emblem', ranked.guild_emblem,
          'level', ranked.guild_level
        ) end,
        'formation', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'cardId', slot.card_id,
            'enhancement', coalesce(pc.enhancement, 0)
          ) order by slot.ord), '[]'::jsonb)
          from unnest(coalesce(ranked.formation, '{}'::text[])) with ordinality as slot(card_id, ord)
          left join public.gacha_s2_player_cards pc
            on pc.user_id = ranked.user_id and pc.card_id = slot.card_id
        ),
        'mine', ranked.user_id = p_user_id
      ) order by ranked.rank)
      from ranked where ranked.rank <= 50
    ), '[]'::jsonb)
  into v_population, v_rank, v_top_fifty_power, v_leaders;

  return jsonb_build_object(
    'seasonId', 'season-2',
    'snapshotAt', public.gacha_s2_now_ms(),
    'population', v_population,
    'leaders', v_leaders,
    'topFiftyPower', v_top_fifty_power,
    'powerToTopFifty', case
      when v_rank <= 50 or v_top_fifty_power = 0 then 0
      else greatest(0, v_top_fifty_power - p_verified_power + 1)
    end,
    'player', jsonb_build_object(
      'nickname', v_nickname,
      'power', p_verified_power,
      'rank', v_rank,
      'guild', v_guild,
      'topPercent', case when v_population = 0 then 100 else round(v_rank::numeric * 100 / v_population, 1) end
    )
  );
end;
$$;

revoke all on function public.gacha_s2_get_power_ranking(uuid, integer) from public, anon, authenticated;
grant execute on function public.gacha_s2_get_power_ranking(uuid, integer) to service_role;
