-- 미니게임 정상화 공지 보상: 모든 유저에게 10,000P를 한 번 지급한다.
update public.gacha_s2_player_states
set points = points + 10000,
    revision = revision + 1,
    updated_at = now();
