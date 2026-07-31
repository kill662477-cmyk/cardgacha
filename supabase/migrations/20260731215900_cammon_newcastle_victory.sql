-- Grant every current Season 2 account 200,000P for Cammon Stars vs Newcastle victory.

begin;

create table if not exists public.gacha_s2_cammon_newcastle_reward_20260731 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  points_before integer not null,
  points_granted integer not null default 200000 check (points_granted = 200000),
  points_after integer,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_cammon_newcastle_reward_20260731 (
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
from public.gacha_s2_cammon_newcastle_reward_20260731 reward
where state.user_id = reward.user_id
  and reward.points_after is null;

update public.gacha_s2_cammon_newcastle_reward_20260731 reward
set points_after = state.points
from public.gacha_s2_player_states state
where state.user_id = reward.user_id
  and reward.points_after is null;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_cammon_newcastle_reward_20260731
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'cammon-newcastle-victory-20260731',
      '[이벤트] 미니대전 캄몬스타즈 승리 기념 · 200,000 P 지급',
      E'미니대전 캄몬스타즈 VS 뉴캣슬 캄몬스타즈 승리를 기념하여 전 계정에 200,000 포인트를 지급해 드립니다!\n\n캄몬스타즈의 승리를 함께 축하해 주세요.',
      'REWARD',
      200000
    );
  end loop;
end
$mail$;

do $$
declare
  v_reward_count integer;
  v_reward_total bigint;
begin
  select count(*), coalesce(sum(points_granted), 0)
  into v_reward_count, v_reward_total
  from public.gacha_s2_cammon_newcastle_reward_20260731;

  if v_reward_count = 0 then
    raise exception 'reward has no target accounts';
  end if;

  if v_reward_total <> v_reward_count::bigint * 200000 then
    raise exception 'reward total mismatch';
  end if;

  if exists (
    select 1
    from public.gacha_s2_cammon_newcastle_reward_20260731
    where points_after is null
       or points_after <> points_before + points_granted
  ) then
    raise exception 'reward amount validation failed';
  end if;
end;
$$;

revoke all on table public.gacha_s2_cammon_newcastle_reward_20260731
  from public, anon, authenticated;

commit;
