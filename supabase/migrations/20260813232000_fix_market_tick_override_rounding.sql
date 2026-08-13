-- A percentage override can exceed its basis-point CHECK by one after integer price rounding.
-- Round toward the previous price, then clamp the reported change as a final guard.
create or replace function public.gacha_s2_apply_market_tick_override()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_override_bps integer;
  v_previous_price integer;
  v_base_price integer;
  v_target_price numeric;
begin
  select change_bps
    into v_override_bps
  from public.gacha_s2_market_tick_overrides
  where symbol = new.symbol
    and hour_at = new.hour_at;

  if v_override_bps is null then
    return new;
  end if;

  select price
    into v_previous_price
  from public.gacha_s2_market_prices
  where symbol = new.symbol
    and hour_at < new.hour_at
  order by hour_at desc
  limit 1;

  select base_price
    into v_base_price
  from public.gacha_s2_market_assets
  where symbol = new.symbol;

  if v_previous_price is null or v_base_price is null then
    raise exception 'Cannot apply market tick override for % at %: reference price is missing',
      new.symbol, new.hour_at;
  end if;

  v_target_price := v_previous_price * (1 + v_override_bps::numeric / 10000);
  new.price := greatest(
    100,
    least(
      v_base_price * 10,
      case
        when v_override_bps < 0 then ceil(v_target_price)::integer
        when v_override_bps > 0 then floor(v_target_price)::integer
        else v_previous_price
      end
    )
  );
  new.change_bps := greatest(
    -3000,
    least(3000, round((new.price::numeric / v_previous_price - 1) * 10000)::integer)
  );
  new.regime := 'shock';
  new.trend_direction := 0;
  new.trend_remaining := 0;
  return new;
end;
$$;

revoke all on function public.gacha_s2_apply_market_tick_override()
  from public, anon, authenticated;

do $$
declare
  v_source text;
begin
  v_source := pg_get_functiondef(
    'public.gacha_s2_apply_market_tick_override()'::regprocedure
  );
  if v_source not like '%when v_override_bps < 0 then ceil(v_target_price)%'
     or v_source not like '%when v_override_bps > 0 then floor(v_target_price)%'
     or v_source not like '%least(3000,%' then
    raise exception 'MARKET_TICK_OVERRIDE_ROUNDING_FIX_FAILED';
  end if;
end;
$$;
