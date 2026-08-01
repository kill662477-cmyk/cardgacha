-- 두두님 특별 요청 기념 20만 포인트 지급

begin;

create table if not exists public.gacha_s2_dudu_request_reward_20260801 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_dudu_request_reward_20260801 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_dudu_request_reward_20260801 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 200000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_dudu_request_reward_20260801
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_dudu_request_reward_20260801
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'dudu-request-reward-20260801',
      '[선물] 🎁 두두님 특별 요청! 200,000 P 깜짝 지급 🎁',
      E'반갑습니다! 두두님의 특별한 요청으로 캄몬스타즈 모든 유저분들께 깜짝 선물이 도착했습니다.\n\n'
      '게임 플레이에 유용하게 쓰일 수 있도록 20만 포인트를 쏩니다!\n'
      '앞으로도 즐거운 모험과 함께 풍성한 시간 보내시길 바랍니다. 캄몬!',
      'REWARD',
      200000
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_dudu_request_reward_20260801
  from public, anon, authenticated;

commit;
