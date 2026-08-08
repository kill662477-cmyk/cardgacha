-- K-중만컵 기념 10만 포인트 다이렉트 지급 및 안내 (캄몬스타즈 응원)

begin;

create table if not exists public.gacha_s2_k_joongman_cup_reward_20260808 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_k_joongman_cup_reward_20260808 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_k_joongman_cup_reward_20260808 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 100000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_k_joongman_cup_reward_20260808
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_k_joongman_cup_reward_20260808
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'k-joongman-cup-reward-20260808',
      '[이벤트] K-중만컵 기념 10만 포인트 특별 지원금!',
      E'K-중만컵 기념으로 모든 유저분들께 10만 포인트를 직접 지급해 드렸습니다!\n\n'
      '(※ 본 10만 포인트는 우편 수령 버튼을 누르실 필요 없이 이미 보유 포인트에 즉시 추가되었습니다.)\n\n'
      '캄몬스타즈 많은 응원 부탁드립니다! 캄몬스타즈 화이팅!! 🎉',
      'SYSTEM',
      0
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_k_joongman_cup_reward_20260808
  from public, anon, authenticated;

commit;
