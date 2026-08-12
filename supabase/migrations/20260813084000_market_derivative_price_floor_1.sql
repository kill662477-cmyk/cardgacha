-- Let leveraged/inverse products reflect losses below 100P. The underlying x1 floor stays 100P.
alter table public.gacha_s2_market_product_prices
  drop constraint if exists gacha_s2_market_product_prices_price_check;
alter table public.gacha_s2_market_product_prices
  add constraint gacha_s2_market_product_prices_price_check check (price >= 1);

alter table public.gacha_s2_market_trades
  drop constraint if exists gacha_s2_market_trades_unit_price_check;
alter table public.gacha_s2_market_trades
  add constraint gacha_s2_market_trades_unit_price_check check (unit_price >= 1);

create or replace function public.gacha_s2_market_ensure_product_prices(p_now timestamptz default now())
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hour timestamptz;
  v_cursor timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext('gacha_s2_market_product_prices'));
  v_hour := public.gacha_s2_market_ensure_prices(p_now);

  if not exists (select 1 from public.gacha_s2_market_product_prices) then
    insert into public.gacha_s2_market_product_prices(
      symbol, position_type, multiplier, hour_at, price, change_bps
    )
    select base.symbol, product.position_type, product.multiplier,
           v_hour, base.price,
           greatest(-15000, least(
             15000,
             base.change_bps * product.multiplier
               * case when product.position_type = 'inverse' then -1 else 1 end
           ))
    from public.gacha_s2_market_prices base
    cross join (values
      ('long'::text, 1::smallint),
      ('long'::text, 2::smallint),
      ('long'::text, 3::smallint),
      ('long'::text, 4::smallint),
      ('long'::text, 5::smallint),
      ('inverse'::text, 2::smallint),
      ('inverse'::text, 3::smallint),
      ('inverse'::text, 4::smallint),
      ('inverse'::text, 5::smallint)
    ) product(position_type, multiplier)
    where base.hour_at = v_hour
    on conflict do nothing;
    return v_hour;
  end if;

  select max(hour_at) + interval '1 hour'
  into v_cursor
  from public.gacha_s2_market_product_prices;

  while v_cursor <= v_hour loop
    insert into public.gacha_s2_market_product_prices(
      symbol, position_type, multiplier, hour_at, price, change_bps
    )
    select calculated.symbol,
           calculated.position_type,
           calculated.multiplier,
           v_cursor,
           calculated.next_price,
           greatest(-15000, least(
             15000,
             round((calculated.next_price::numeric / calculated.previous_product_price - 1) * 10000)::integer
           ))
    from (
      select asset.symbol,
             product.position_type,
             product.multiplier,
             previous_product.price as previous_product_price,
             greatest(
               case when product.position_type = 'long' and product.multiplier = 1 then 100 else 1 end,
               least(
                 asset.base_price * 10,
                 round(previous_product.price * (
                   1 + ((current_underlying.price::numeric / previous_underlying.price) - 1)
                     * product.multiplier
                     * case when product.position_type = 'inverse' then -1 else 1 end
                 ))::integer
               )
             ) as next_price
      from public.gacha_s2_market_assets asset
      cross join (values
        ('long'::text, 1::smallint),
        ('long'::text, 2::smallint),
        ('long'::text, 3::smallint),
        ('long'::text, 4::smallint),
        ('long'::text, 5::smallint),
        ('inverse'::text, 2::smallint),
        ('inverse'::text, 3::smallint),
        ('inverse'::text, 4::smallint),
        ('inverse'::text, 5::smallint)
      ) product(position_type, multiplier)
      join public.gacha_s2_market_prices current_underlying
        on current_underlying.symbol = asset.symbol and current_underlying.hour_at = v_cursor
      join public.gacha_s2_market_prices previous_underlying
        on previous_underlying.symbol = asset.symbol and previous_underlying.hour_at = v_cursor - interval '1 hour'
      join public.gacha_s2_market_product_prices previous_product
        on previous_product.symbol = asset.symbol
       and previous_product.position_type = product.position_type
       and previous_product.multiplier = product.multiplier
       and previous_product.hour_at = v_cursor - interval '1 hour'
      where asset.active
    ) calculated
    on conflict do nothing;
    v_cursor := v_cursor + interval '1 hour';
  end loop;

  return v_hour;
end;
$$;

revoke all on function public.gacha_s2_market_ensure_product_prices(timestamptz) from public, anon, authenticated;
grant execute on function public.gacha_s2_market_ensure_product_prices(timestamptz) to service_role;

do $$
declare
  v_source text;
begin
  v_source := pg_get_functiondef(
    'public.gacha_s2_market_ensure_product_prices(timestamptz)'::regprocedure
  );
  if v_source not like '%then 100 else 1 end%' then
    raise exception 'MARKET_DERIVATIVE_PRICE_FLOOR_GUARD_FAILED';
  end if;
end;
$$;
