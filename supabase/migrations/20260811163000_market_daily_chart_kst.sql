-- 캄스증권 차트는 한국시간 자정에 새 일봉 화면으로 전환한다.
-- 가격과 보유 포지션은 계속 유지하고, 차트에 내려주는 시간봉만 당일 00시 이후로 제한한다.

create or replace function public.gacha_s2_get_market_state(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hour timestamptz;
  v_day_start timestamptz;
  v_revision bigint;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', '로그인이 필요합니다.');
  end if;
  select revision into v_revision from public.gacha_s2_player_states where user_id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', '계정 상태를 찾을 수 없습니다.');
  end if;

  v_hour := public.gacha_s2_market_ensure_prices(now());
  v_day_start := date_trunc('day', v_hour at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';

  return jsonb_build_object(
    'hourAt', floor(extract(epoch from v_hour) * 1000)::bigint,
    'historyStartsAt', floor(extract(epoch from v_day_start) * 1000)::bigint,
    'nextUpdateAt', floor(extract(epoch from (v_hour + interval '1 hour')) * 1000)::bigint,
    'playerRevision', v_revision,
    'feeRate', 0.015,
    'totalInvestmentCap', 500000,
    'perAssetInvestmentCap', 500000,
    'investedPoints', coalesce((
      select sum(cost_basis) from public.gacha_s2_market_holdings where user_id = p_user_id
    ), 0),
    'marketValue', coalesce((
      select sum(h.quantity::bigint * p.price)
      from public.gacha_s2_market_holdings h
      join public.gacha_s2_market_prices p on p.symbol = h.symbol and p.hour_at = v_hour
      where h.user_id = p_user_id
    ), 0),
    'realizedPnl', coalesce((
      select sum(realized_pnl) from public.gacha_s2_market_trades where user_id = p_user_id
    ), 0),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'symbol', a.symbol,
        'name', a.display_name,
        'cardId', a.card_id,
        'price', p.price,
        'changeBps', p.change_bps,
        'regime', p.regime,
        'quantity', coalesce(h.quantity, 0),
        'costBasis', coalesce(h.cost_basis, 0),
        'averagePrice', case when coalesce(h.quantity, 0) > 0
          then round(h.cost_basis::numeric / h.quantity)::bigint else 0 end,
        'marketValue', coalesce(h.quantity::bigint * p.price, 0),
        'unrealizedPnl', coalesce(h.quantity::bigint * p.price - h.cost_basis, 0),
        'history', coalesce(history.rows, '[]'::jsonb)
      ) order by a.sort_order)
      from public.gacha_s2_market_assets a
      join public.gacha_s2_market_prices p on p.symbol = a.symbol and p.hour_at = v_hour
      left join public.gacha_s2_market_holdings h on h.user_id = p_user_id and h.symbol = a.symbol
      left join lateral (
        select jsonb_agg(jsonb_build_object(
          'at', floor(extract(epoch from samples.hour_at) * 1000)::bigint,
          'price', samples.price
        ) order by samples.hour_at) as rows
        from (
          select hour_at, price
          from public.gacha_s2_market_prices
          where symbol = a.symbol
            and hour_at >= v_day_start
            and hour_at <= v_hour
          order by hour_at desc
          limit 24
        ) samples
      ) history on true
      where a.active
    ), '[]'::jsonb),
    'recentTrades', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tradeId', t.trade_id,
        'symbol', t.symbol,
        'name', a.display_name,
        'side', t.side,
        'quantity', t.quantity,
        'unitPrice', t.unit_price,
        'feePoints', t.fee_points,
        'netPoints', t.net_points,
        'realizedPnl', t.realized_pnl,
        'tradedAt', floor(extract(epoch from t.traded_at) * 1000)::bigint
      ) order by t.traded_at desc)
      from (
        select * from public.gacha_s2_market_trades
        where user_id = p_user_id
        order by traded_at desc
        limit 20
      ) t
      join public.gacha_s2_market_assets a on a.symbol = t.symbol
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.gacha_s2_get_market_state(uuid) from public, anon, authenticated;
grant execute on function public.gacha_s2_get_market_state(uuid) to service_role;

do $$
declare
  v_src text;
begin
  v_src := pg_get_functiondef('public.gacha_s2_get_market_state(uuid)'::regprocedure);
  if v_src not like '%Asia/Seoul%'
     or v_src not like '%hour_at >= v_day_start%'
     or v_src not like '%historyStartsAt%' then
    raise exception 'MARKET_DAILY_CHART_GUARD_FAILED';
  end if;
end;
$$;
