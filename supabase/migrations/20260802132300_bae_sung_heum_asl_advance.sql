-- ASL 예선 2일차 배성흠Z 본선진출 기념 10만포인트 지급

begin;

create table if not exists public.gacha_s2_asl_bae_sung_heum_reward_20260802 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_asl_bae_sung_heum_reward_20260802 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_asl_bae_sung_heum_reward_20260802 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 100000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_asl_bae_sung_heum_reward_20260802
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_asl_bae_sung_heum_reward_20260802
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'asl-bae-sung-heum-advance-20260802',
      '[축하] 🌟ASL 본선 진출🌟 배성흠Z 코치! 100,000 P 지급',
      E'🎉 ASL 예선 2일차! 배성흠Z 코치님의 본선 진출을 축하합니다! 🎉\n\n'
      '멋진 경기력으로 당당히 본선행 티켓을 거머쥔 배성흠Z 코치님의 눈부신 활약을 기념하며, '
      '모든 유저분들께 10만 포인트를 쏩니다! 🎁\n\n'
      '앞으로 펼쳐질 본선 무대에서도 배성흠Z 코치님의 맹활약을 함께 응원해 주세요! 화이팅!',
      'REWARD',
      100000
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_asl_bae_sung_heum_reward_20260802
  from public, anon, authenticated;

commit;
