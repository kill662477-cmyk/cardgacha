-- 월드보스 보상 티어를 6개 -> 8개로 확장(3,000만/4,000만 추가)하면서
-- claimed_tier 인덱스가 6·7까지 늘었으나, 기존 CHECK 제약이 claimed_tier <= 5 로 고정돼
-- 새 상위 티어 처치자가 보상 수령 시 check constraint 위반으로 "요청 처리 실패" 발생.
-- 상한을 15로 넓혀 향후 티어 추가에도 여유를 둔다. (실패한 claim은 트랜잭션 롤백돼 데이터 손상 없음)
alter table public.gacha_s2_world_boss_players
  drop constraint if exists gacha_s2_world_boss_players_claimed_tier_check;
alter table public.gacha_s2_world_boss_players
  add constraint gacha_s2_world_boss_players_claimed_tier_check
  check (claimed_tier >= -1 and claimed_tier <= 15);
