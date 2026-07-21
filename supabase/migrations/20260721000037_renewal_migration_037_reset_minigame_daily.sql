-- 일일 미니게임 포인트 획득량 및 횟수 초기화 (테스트용)
delete from public.gacha_s2_minigame_daily
where play_date = timezone('Asia/Seoul', now())::date;

-- 미니게임 진행 중인 세션(active)도 모두 정리하여 꼬임 방지
update public.gacha_s2_minigame_runs
set status = 'completed'
where status = 'active';
