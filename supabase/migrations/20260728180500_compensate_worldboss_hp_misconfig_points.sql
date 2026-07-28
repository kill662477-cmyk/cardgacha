-- 20260728174500 의 안내 우편은 표시 전용이다. gacha_s2_get_mailbox 는 points 를 읽어
-- 보여주기만 하고, 우편을 수령해 포인트를 적립하는 커맨드가 없다.
-- (직전 kammon_bgm_victory 지급도 우편은 안내, 실제 적립은 별도 update 였다.)
-- 그래서 전 계정에 30,000 P 를 직접 지급한다.
update public.gacha_s2_player_states
set points = points + 30000,
    revision = revision + 1,
    updated_at = now();
