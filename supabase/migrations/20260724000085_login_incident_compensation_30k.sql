-- Grant every current Season 2 account 30,000P for the login incident.

begin;
create table if not exists public.gacha_s2_login_incident_reward_20260724 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  points_before integer not null,
  points_granted integer not null default 30000 check (points_granted = 30000),
  points_after integer,
  granted_at timestamptz not null default now()
);
insert into public.gacha_s2_login_incident_reward_20260724 (
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
from public.gacha_s2_login_incident_reward_20260724 reward
where state.user_id = reward.user_id
  and reward.points_after is null;
update public.gacha_s2_login_incident_reward_20260724 reward
set points_after = state.points
from public.gacha_s2_player_states state
where state.user_id = reward.user_id
  and reward.points_after is null;
do $$
declare
  v_reward_count integer;
  v_reward_total bigint;
begin
  select count(*), coalesce(sum(points_granted), 0)
  into v_reward_count, v_reward_total
  from public.gacha_s2_login_incident_reward_20260724;

  if v_reward_count = 0 then
    raise exception 'login incident reward has no target accounts';
  end if;

  if v_reward_total <> v_reward_count::bigint * 30000 then
    raise exception 'login incident reward total mismatch';
  end if;

  if exists (
    select 1
    from public.gacha_s2_login_incident_reward_20260724
    where points_after is null
       or points_after <> points_before + points_granted
  ) then
    raise exception 'login incident reward amount validation failed';
  end if;
end;
$$;
revoke all on table public.gacha_s2_login_incident_reward_20260724
  from public, anon, authenticated;
commit;
