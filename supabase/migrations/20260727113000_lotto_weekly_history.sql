-- Read-only seven-day history bundled into the existing lotto state response.
create or replace function public.gacha_s2_get_lotto_history(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_window_start timestamptz :=
    (((now() at time zone 'Asia/Seoul')::date - 6)::timestamp at time zone 'Asia/Seoul');
begin
  if p_user_id is null or not exists (
    select 1 from public.gacha_s2_accounts where id = p_user_id
  ) then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;

  return jsonb_build_object(
    'ok', true,
    'windowDays', 7,
    'history', coalesce((
      select jsonb_agg(history.payload order by history.draw_at desc)
      from (
        select round.draw_at, jsonb_build_object(
          'roundId', round.round_id,
          'drawAt', floor(extract(epoch from round.draw_at) * 1000)::bigint,
          'winningNumbers', to_jsonb(round.winning_numbers),
          'firstWinners', round.first_winners,
          'secondWinners', round.second_winners
        ) payload
        from public.gacha_s2_lotto_rounds round
        where round.status = 'drawn'
          and round.draw_at >= v_window_start
        order by round.draw_at desc
        limit 21
      ) history
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.gacha_s2_get_lotto_state_v2(p_user_id uuid)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.gacha_s2_get_lotto_state(p_user_id)
    || jsonb_build_object(
      'history',
      coalesce(
        (public.gacha_s2_get_lotto_history(p_user_id))->'history',
        '[]'::jsonb
      )
    );
$$;

revoke all on function public.gacha_s2_get_lotto_history(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.gacha_s2_get_lotto_state_v2(uuid)
  from public, anon, authenticated;
grant execute on function public.gacha_s2_get_lotto_state_v2(uuid)
  to service_role;
