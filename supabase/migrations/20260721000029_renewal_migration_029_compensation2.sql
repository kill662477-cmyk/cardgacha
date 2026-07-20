-- 20,000 points compensation and thank you gift to all users
UPDATE public.gacha_s2_player_states
SET points = points + 20000,
    revision = revision + 1,
    updated_at = now();
