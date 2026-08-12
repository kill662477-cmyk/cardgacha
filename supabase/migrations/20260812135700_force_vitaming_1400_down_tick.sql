-- One-off operator event: force VTM (비타밍) to close 10% lower at 2026-08-12 14:00 KST.
-- Pre-seeding the hourly row makes the normal deterministic generator skip only this symbol/hour.
do $$
declare
  v_hour constant timestamptz := timestamptz '2026-08-12 14:00:00+09';
  v_previous_price integer;
  v_price integer;
begin
  select price
    into v_previous_price
  from public.gacha_s2_market_prices
  where symbol = 'VTM'
    and hour_at < v_hour
  order by hour_at desc
  limit 1;

  if v_previous_price is null then
    raise exception 'Cannot force VTM down tick: previous market price is missing';
  end if;

  v_price := greatest(100, round(v_previous_price * 0.90)::integer);

  insert into public.gacha_s2_market_prices(
    symbol,
    hour_at,
    price,
    change_bps,
    regime,
    trend_direction,
    trend_remaining
  ) values (
    'VTM',
    v_hour,
    v_price,
    round((v_price::numeric / v_previous_price - 1) * 10000)::integer,
    'shock',
    0,
    0
  )
  on conflict (symbol, hour_at) do update
  set price = excluded.price,
      change_bps = excluded.change_bps,
      regime = excluded.regime,
      trend_direction = excluded.trend_direction,
      trend_remaining = excluded.trend_remaining;
end;
$$;
