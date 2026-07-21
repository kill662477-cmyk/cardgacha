-- 미니게임 버그 조치 완료 시점까지 메뉴 폐쇄 안내 및 사과 보상 2만 포인트 지급
update public.gacha_s2_player_states
set points = points + 20000;
