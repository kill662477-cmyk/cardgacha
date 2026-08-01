-- Migration-history alias only.
-- Production received the world-boss HP migration under version 20260801120848.
-- The replayable SQL remains in 20260801204500_worldboss_hp_140_150_160_180.sql.
-- On production, version 20260801204500 is marked applied without executing it again.

select 1;
