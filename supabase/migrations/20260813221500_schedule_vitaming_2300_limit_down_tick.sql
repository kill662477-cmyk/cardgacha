-- Operator event: force VTM (비타밍) to the -30.00% limit at the next hourly tick.
insert into public.gacha_s2_market_tick_overrides(symbol, hour_at, change_bps, reason)
values (
  'VTM',
  timestamptz '2026-08-13 23:00:00+09',
  -3000,
  'operator-2026-08-13-vtm-next-limit-down'
)
on conflict (symbol, hour_at) do update
set change_bps = excluded.change_bps,
    reason = excluded.reason;
