-- Protect deeply depressed underlying assets without turning the market into fixed oscillation.
-- Operator tick overrides still win because their trigger runs after this alphabetically.

create or replace function public.gacha_s2_apply_market_low_price_recovery()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_previous_price integer;
  v_base_price integer;
  v_seed text;
  v_direction_roll numeric;
  v_magnitude_roll numeric;
  v_length_roll numeric;
  v_rate numeric;
begin
  select price into v_previous_price
  from public.gacha_s2_market_prices
  where symbol = new.symbol
    and hour_at < new.hour_at
  order by hour_at desc
  limit 1;

  select base_price into v_base_price
  from public.gacha_s2_market_assets
  where symbol = new.symbol;

  if v_previous_price is null or v_base_price is null then
    return new;
  end if;

  v_seed := new.symbol || ':'
    || to_char(new.hour_at at time zone 'UTC', 'YYYYMMDDHH24');

  if v_previous_price < v_base_price * 0.10 then
    -- Critical zone: start a deterministic 2-4 tick recovery trend.
    v_magnitude_roll := public.gacha_s2_market_random(v_seed || ':low-recovery-magnitude');
    v_length_roll := public.gacha_s2_market_random(v_seed || ':low-recovery-length');
    v_rate := 0.08 + v_magnitude_roll * 0.12;
    new.price := greatest(
      100,
      least(v_base_price * 10, round(v_previous_price * (1 + v_rate))::integer)
    );
    new.change_bps := round((new.price::numeric / v_previous_price - 1) * 10000)::integer;
    new.regime := 'trend';
    new.trend_direction := 1;
    new.trend_remaining := floor(1 + v_length_roll * 3)::smallint;
    return new;
  end if;

  if v_previous_price < v_base_price * 0.20 then
    -- Depressed zone: a down trend cannot persist. Seeded 75% recovery chance per tick.
    if new.trend_direction = -1 then
      new.trend_remaining := 0;
    end if;

    v_direction_roll := public.gacha_s2_market_random(v_seed || ':low-recovery-direction');
    if v_direction_roll < 0.75 then
      v_magnitude_roll := public.gacha_s2_market_random(v_seed || ':low-recovery-magnitude');
      v_rate := 0.02 + v_magnitude_roll * 0.08;
      new.price := greatest(
        100,
        least(v_base_price * 10, round(v_previous_price * (1 + v_rate))::integer)
      );
      new.change_bps := round((new.price::numeric / v_previous_price - 1) * 10000)::integer;
      new.regime := 'normal';
      new.trend_direction := 0;
      new.trend_remaining := 0;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists gacha_s2_00_apply_market_low_price_recovery_trigger
  on public.gacha_s2_market_prices;
create trigger gacha_s2_00_apply_market_low_price_recovery_trigger
before insert on public.gacha_s2_market_prices
for each row execute function public.gacha_s2_apply_market_low_price_recovery();

revoke all on function public.gacha_s2_apply_market_low_price_recovery()
  from public, anon, authenticated;

do $verify$
declare
  v_source text;
begin
  v_source := pg_get_functiondef(
    'public.gacha_s2_apply_market_low_price_recovery()'::regprocedure
  );

  if v_source not like '%v_previous_price < v_base_price * 0.10%'
     or v_source not like '%v_previous_price < v_base_price * 0.20%'
     or v_source not like '%v_direction_roll < 0.75%'
     or v_source not like '%new.trend_direction := 1%'
     or v_source not like '%new.trend_remaining := floor(1 + v_length_roll * 3)%'
  then
    raise exception 'MARKET_LOW_PRICE_RECOVERY_GUARD_FAILED';
  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.gacha_s2_market_prices'::regclass
      and tgname = 'gacha_s2_00_apply_market_low_price_recovery_trigger'
      and not tgisinternal
  ) then
    raise exception 'MARKET_LOW_PRICE_RECOVERY_TRIGGER_MISSING';
  end if;
end
$verify$;
