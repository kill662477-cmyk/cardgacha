-- Operator-scheduled market ticks. Overrides are applied only when the normal hourly row is generated.
create table if not exists public.gacha_s2_market_tick_overrides (
  symbol text not null references public.gacha_s2_market_assets(symbol) on delete cascade,
  hour_at timestamptz not null,
  change_bps integer not null check (change_bps between -3000 and 3000),
  reason text not null default 'operator',
  created_at timestamptz not null default now(),
  primary key (symbol, hour_at)
);

alter table public.gacha_s2_market_tick_overrides enable row level security;
revoke all on table public.gacha_s2_market_tick_overrides from public, anon, authenticated;

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

  new.price := greatest(
    100,
    least(
      v_base_price * 10,
      round(v_previous_price * (1 + v_override_bps::numeric / 10000))::integer
    )
  );
  new.change_bps := round((new.price::numeric / v_previous_price - 1) * 10000)::integer;
  new.regime := 'shock';
  new.trend_direction := 0;
  new.trend_remaining := 0;
  return new;
end;
$$;

drop trigger if exists gacha_s2_apply_market_tick_override_trigger
  on public.gacha_s2_market_prices;
create trigger gacha_s2_apply_market_tick_override_trigger
before insert on public.gacha_s2_market_prices
for each row execute function public.gacha_s2_apply_market_tick_override();

revoke all on function public.gacha_s2_apply_market_tick_override() from public, anon, authenticated;

insert into public.gacha_s2_market_tick_overrides(symbol, hour_at, change_bps, reason)
values
  ('TMT', timestamptz '2026-08-12 19:00:00+09', -2998, 'operator-2026-08-12'),
  ('NGN', timestamptz '2026-08-12 19:00:00+09', -865, 'operator-2026-08-12')
on conflict (symbol, hour_at) do update
set change_bps = excluded.change_bps,
    reason = excluded.reason;
