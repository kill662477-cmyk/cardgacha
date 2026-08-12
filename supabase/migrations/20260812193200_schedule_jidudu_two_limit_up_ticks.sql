-- Operator event: schedule two consecutive near-limit-up ticks for JDD (지두두).
insert into public.gacha_s2_market_tick_overrides(symbol, hour_at, change_bps, reason)
values
  ('JDD', timestamptz '2026-08-12 20:00:00+09', 2987, 'operator-2026-08-12-two-limit-up'),
  ('JDD', timestamptz '2026-08-12 21:00:00+09', 2964, 'operator-2026-08-12-two-limit-up')
on conflict (symbol, hour_at) do update
set change_bps = excluded.change_bps,
    reason = excluded.reason;
