-- Card Gacha Season 2: fix wrong podium photo for players without a chosen
-- representative card.
--
-- gacha_s2_get_power_ranking returned representative_card_id as-is (often NULL --
-- players never explicitly set one). The client's podium renderer then fell back
-- to a hardcoded per-rank placeholder card (PODIUM_CARD_IDS, e.g. kimyunhwan-2 for
-- rank 1) and displayed it as if it were that player's own card -- misleading, and
-- the reported bug: rank 1's podium photo wasn't their real representative card.
--
-- Fix: fall back to the player's own first formation slot (a card they actually
-- equipped) instead of an unrelated fixed default. No client change needed --
-- ranking-controller.js already renders whatever representativeCardId it receives.

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

  with ranked as (
    select state.user_id,
      account.nickname,
      state.power_snapshot,
      state.power_snapshot_at,
      coalesce(state.representative_card_id, state.formation[1]) as representative_card_id,
      row_number() over (
        order by state.power_snapshot desc, state.power_snapshot_at asc nulls last, state.user_id
      )::integer as rank
    from public.gacha_s2_player_states state
    join public.gacha_s2_accounts account on account.id = state.user_id
  )
  select
    (select count(*)::integer from ranked),
    (select rank from ranked where user_id = p_user_id),
    coalesce((select power_snapshot from ranked where rank = 50), 0),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', rank,
        'nickname', nickname,
        'power', power_snapshot,
        'representativeCardId', representative_card_id,
        'mine', user_id = p_user_id
      ) order by rank)
      from ranked where rank <= 50
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
      'topPercent', case when v_population = 0 then 100 else round(v_rank::numeric * 100 / v_population, 1) end
    )
  );
end;
$$;

revoke all on function public.gacha_s2_get_power_ranking(uuid, integer) from public, anon, authenticated;
