-- 8월 3일 이후 신규 가입자 100만 포인트 직접 지급 (안내 우편 없음)

begin;

create table if not exists public.gacha_s2_aug_3_newbie_1m_points_20260806 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_aug_3_newbie_1m_points_20260806 (user_id)
select id from public.gacha_s2_accounts
where created_at >= '2026-08-02 15:00:00+00' -- 2026-08-03 00:00:00 KST
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_aug_3_newbie_1m_points_20260806 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 1000000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_aug_3_newbie_1m_points_20260806
set granted = true, granted_at = now()
where granted = false;

revoke all on table public.gacha_s2_aug_3_newbie_1m_points_20260806
  from public, anon, authenticated;

commit;
