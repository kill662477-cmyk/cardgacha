-- 미니게임 진행 중인 세션(active) 모두 정리하여 꼬임 방지
update public.gacha_s2_minigame_runs
set status = 'completed'
where status = 'active';
