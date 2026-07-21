-- Refill action energy for all accounts
update public.gacha_s2_player_states 
set action_energy = max_action_energy, 
    last_energy_at = now();
