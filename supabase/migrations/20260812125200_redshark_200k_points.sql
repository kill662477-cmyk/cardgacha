-- 빨간상어~ 계정 20만 포인트 안내 없이 추가 지급

begin;

create table if not exists public.gacha_s2_redshark_200k_points_20260812 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_redshark_200k_points_20260812 (user_id)
select id from public.gacha_s2_accounts
where nickname = '빨간상어~'
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_redshark_200k_points_20260812 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 200000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_redshark_200k_points_20260812
set granted = true, granted_at = now()
where granted = false;

revoke all on table public.gacha_s2_redshark_200k_points_20260812
  from public, anon, authenticated;

commit;
