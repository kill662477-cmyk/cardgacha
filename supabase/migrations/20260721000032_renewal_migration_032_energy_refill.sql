-- Refill action energy for all users
UPDATE public.gacha_s2_player_states
SET action_energy = max_action_energy,
    revision = revision + 1;
