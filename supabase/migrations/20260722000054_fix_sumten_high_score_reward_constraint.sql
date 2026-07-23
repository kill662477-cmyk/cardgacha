-- Sum Ten can award up to 3,000P, but the run audit column still had the
-- Memory Advanced ceiling of 1,500P. High-score finishes therefore rolled back.

alter table public.gacha_s2_minigame_runs
  drop constraint if exists gacha_s2_minigame_runs_reward_points_check;

alter table public.gacha_s2_minigame_runs
  add constraint gacha_s2_minigame_runs_reward_points_check
  check (reward_points between 0 and 3000);
