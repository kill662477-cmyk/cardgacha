-- A derivative at the 1P floor can be sold, but cannot accept new buy orders.
-- This trigger runs inside the market-trade transaction, so a rejected trade rolls back points and holdings too.
create or replace function public.gacha_s2_reject_derivative_buy_at_floor()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.side = 'buy'
     and new.multiplier >= 2
     and new.unit_price <= 1 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKET_PRODUCT_BUY_SUSPENDED';
  end if;
  return new;
end;
$$;

drop trigger if exists gacha_s2_reject_derivative_buy_at_floor_trigger
  on public.gacha_s2_market_trades;
create trigger gacha_s2_reject_derivative_buy_at_floor_trigger
before insert on public.gacha_s2_market_trades
for each row execute function public.gacha_s2_reject_derivative_buy_at_floor();

revoke all on function public.gacha_s2_reject_derivative_buy_at_floor() from public, anon, authenticated;

do $$
declare
  v_source text;
begin
  v_source := pg_get_functiondef(
    'public.gacha_s2_reject_derivative_buy_at_floor()'::regprocedure
  );
  if v_source not like '%new.side = ''buy''%'
     or v_source not like '%new.multiplier >= 2%'
     or v_source not like '%new.unit_price <= 1%'
     or v_source not like '%MARKET_PRODUCT_BUY_SUSPENDED%' then
    raise exception 'MARKET_1P_BUY_GUARD_FAILED';
  end if;
end;
$$;
