-- Card Gacha Season 2: persist SOOP OAuth refresh_token for the donation bridge.
-- Already applied to production via MCP on 2026-07-19 (additive, non-destructive).
-- Companion code change: supabase/functions/soop-bridge/index.ts, src/renewal/soop-bridge.js.

alter table public.gacha_s2_streamer_bridges
  add column if not exists soop_refresh_token_ciphertext text,
  add column if not exists soop_refresh_token_iv text,
  add column if not exists soop_refresh_updated_at timestamptz;
