-- rewardTiers 확장으로 최고 보상이 10,000P -> 30,000P(3,000만 20,000 / 4,000만 30,000)로 늘었으나
-- reward_points CHECK 제약이 <= 10000 으로 고정돼 상위 티어 처치자 보상 수령 시 위반.
-- 상한을 100,000으로 넓혀 향후 티어 상향에도 여유를 둔다. (실패한 claim은 트랜잭션 롤백돼 데이터 손상 없음)
alter table public.gacha_s2_world_boss_players
  drop constraint if exists gacha_s2_world_boss_players_reward_points_check;
alter table public.gacha_s2_world_boss_players
  add constraint gacha_s2_world_boss_players_reward_points_check
  check (reward_points >= 0 and reward_points <= 100000);
