-- 유저의 일일 미니게임 진행도 캐시를 다시 계산하여 덮어씌움
update public.gacha_s2_player_states
set mini_games = public.gacha_s2_minigame_state(user_id, timezone('Asia/Seoul', now())::date);
