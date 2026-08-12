-- Operator event: schedule 20%+ up ticks for SJY (소주양) and VTM (비타밍).
insert into public.gacha_s2_market_tick_overrides(symbol, hour_at, change_bps, reason)
values
  ('SJY', timestamptz '2026-08-12 20:00:00+09', 2271, 'operator-2026-08-12-20h-up'),
  ('VTM', timestamptz '2026-08-12 20:00:00+09', 2438, 'operator-2026-08-12-20h-up')
on conflict (symbol, hour_at) do update
set change_bps = excluded.change_bps,
    reason = excluded.reason;
