-- 우편함은 안내 표시 전용이라 points 필드로는 실제 지급이 되지 않는다.
-- 20260728174500 에서 보낸 안내 우편에 맞춰 전 계정에 30,000 P 를 직접 지급한다.
update public.gacha_s2_player_states
set points = points + 30000,
    revision = revision + 1,
    updated_at = now();;
