-- ASL 예선 1일차 캄몬스타즈 유일신 김윤환 본선진출 기념 50만포인트 지급

begin;

create table if not exists public.gacha_s2_asl_kim_yoon_hwan_reward_20260801 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  points_before integer not null,
  points_granted integer not null default 500000 check (points_granted = 500000),
  points_after integer,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_asl_kim_yoon_hwan_reward_20260801 (
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
from public.gacha_s2_asl_kim_yoon_hwan_reward_20260801 reward
where state.user_id = reward.user_id
  and reward.points_after is null;

update public.gacha_s2_asl_kim_yoon_hwan_reward_20260801 reward
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
    select user_id from public.gacha_s2_asl_kim_yoon_hwan_reward_20260801
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'asl-kim-yoon-hwan-advance-20260801',
      '[축하] 🌟ASL 본선 진출🌟 캄몬스타즈의 유일신 김윤환! 500,000 P 지급',
      E'🎉 ASL 예선 1일차! 캄몬스타즈의 유일신, 빛윤환(김윤환) 코치님의 본선 진출을 격하게 축하합니다! 🎉\n\n'
      '압도적인 경기력으로 당당히 본선행 티켓을 거머쥔 김윤환 코치님의 눈부신 활약을 기념하며, '
      '모든 유저분들께 50만 포인트를 쏩니다! 🎁\n\n'
      '앞으로 펼쳐질 본선 무대에서도 캄몬스타즈 유일신의 끝없는 비상을 함께 응원해 주세요! 화이팅!',
      'REWARD',
      500000
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
  from public.gacha_s2_asl_kim_yoon_hwan_reward_20260801;

  if v_reward_count = 0 then
    raise exception 'reward has no target accounts';
  end if;

  if v_reward_total <> v_reward_count::bigint * 500000 then
    raise exception 'reward total mismatch';
  end if;

  if exists (
    select 1
    from public.gacha_s2_asl_kim_yoon_hwan_reward_20260801
    where points_after is null
       or points_after <> points_before + points_granted
  ) then
    raise exception 'reward amount validation failed';
  end if;
end;
$$;

revoke all on table public.gacha_s2_asl_kim_yoon_hwan_reward_20260801
  from public, anon, authenticated;

commit;
