-- Grant every current Season 2 account 50,000P for the SS/SSS buff and new SS card release.

begin;

lock table public.gacha_s2_player_states in share row exclusive mode;

create table if not exists public.gacha_s2_ss_sss_buff_reward_20260723 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  points_before integer not null,
  points_granted integer not null default 50000 check (points_granted = 50000),
  points_after integer,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_ss_sss_buff_reward_20260723 (
  user_id,
  points_before
)
select state.user_id, state.points
from public.gacha_s2_player_states state
on conflict (user_id) do nothing;

update public.gacha_s2_player_states state
set points = state.points + reward.points_granted,
    revision = state.revision + 1,
    updated_at = now()
from public.gacha_s2_ss_sss_buff_reward_20260723 reward
where state.user_id = reward.user_id
  and reward.points_after is null;

update public.gacha_s2_ss_sss_buff_reward_20260723 reward
set points_after = state.points
from public.gacha_s2_player_states state
where state.user_id = reward.user_id
  and reward.points_after is null;

do $$
declare
  v_player_count integer;
  v_reward_count integer;
  v_reward_total bigint;
begin
  select count(*) into v_player_count
  from public.gacha_s2_player_states;

  select count(*), coalesce(sum(points_granted), 0)
  into v_reward_count, v_reward_total
  from public.gacha_s2_ss_sss_buff_reward_20260723;

  if v_reward_count <> v_player_count then
    raise exception 'SS/SSS global reward target count mismatch: players %, rewards %',
      v_player_count, v_reward_count;
  end if;

  if v_reward_total <> v_reward_count::bigint * 50000 then
    raise exception 'SS/SSS global reward total mismatch';
  end if;

  if exists (
    select 1
    from public.gacha_s2_ss_sss_buff_reward_20260723
    where points_after is null
       or points_after <> points_before + points_granted
  ) then
    raise exception 'SS/SSS global reward amount validation failed';
  end if;
end;
$$;

revoke all on table public.gacha_s2_ss_sss_buff_reward_20260723
  from public, anon, authenticated;

commit;
