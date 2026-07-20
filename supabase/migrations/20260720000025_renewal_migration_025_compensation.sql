-- 10,000 points compensation to all users for the connection lost error
UPDATE public.gacha_s2_player_states
SET points = points + 10000,
    revision = revision + 1,
    updated_at = now();
