-- Mstz_손실바 제외 스트리머 계정 50만 포인트 지급

begin;

create table if not exists public.gacha_s2_streamer_bonus_20260802 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_streamer_bonus_20260802 (user_id)
select id from public.gacha_s2_accounts
where is_streamer = true
  and lower(btrim(nickname)) <> lower('MSTZ_손실바')
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_streamer_bonus_20260802 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 500000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_streamer_bonus_20260802
set granted = true, granted_at = now()
where granted = false;



revoke all on table public.gacha_s2_streamer_bonus_20260802
  from public, anon, authenticated;

commit;
