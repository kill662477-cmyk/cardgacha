-- 8월 3일 이후 신규 가입자 100만 포인트 지급 롤백

begin;

alter table public.gacha_s2_aug_3_newbie_1m_points_20260806
add column if not exists revoked boolean not null default false,
add column if not exists revoked_at timestamptz;

with pending_revokes as (
  select user_id from public.gacha_s2_aug_3_newbie_1m_points_20260806
  where granted = true and revoked = false
)
update public.gacha_s2_player_states state
set points = greatest(0, points - 1000000),
    revision = revision + 1,
    updated_at = now()
from pending_revokes
where state.user_id = pending_revokes.user_id;

update public.gacha_s2_aug_3_newbie_1m_points_20260806
set revoked = true, revoked_at = now()
where granted = true and revoked = false;

commit;
