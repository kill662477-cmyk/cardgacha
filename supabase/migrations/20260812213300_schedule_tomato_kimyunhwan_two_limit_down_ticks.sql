-- Operator event: schedule two consecutive near-limit-down ticks for TMT and KYH.
insert into public.gacha_s2_market_tick_overrides(symbol, hour_at, change_bps, reason)
values
  ('TMT', timestamptz '2026-08-12 22:00:00+09', -2991, 'operator-2026-08-12-two-limit-down'),
  ('TMT', timestamptz '2026-08-12 23:00:00+09', -2973, 'operator-2026-08-12-two-limit-down'),
  ('KYH', timestamptz '2026-08-12 22:00:00+09', -2991, 'operator-2026-08-12-two-limit-down'),
  ('KYH', timestamptz '2026-08-12 23:00:00+09', -2973, 'operator-2026-08-12-two-limit-down')
on conflict (symbol, hour_at) do update
set change_bps = excluded.change_bps,
    reason = excluded.reason;
