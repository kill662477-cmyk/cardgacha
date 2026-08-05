-- K-중만컵 비방 연습 전야제 20만 포인트 다이렉트 지급 및 안내 우편

begin;

create table if not exists public.gacha_s2_unbroadcasted_practice_reward_20260805 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_unbroadcasted_practice_reward_20260805 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_unbroadcasted_practice_reward_20260805 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 200000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_unbroadcasted_practice_reward_20260805
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_unbroadcasted_practice_reward_20260805
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'unbroadcasted-practice-reward-20260805',
      '[이벤트] K-중만컵 비방 연습 전야제 특별 지원금! 💌',
      E'내일이면 선수, 코치분들의 K-중만컵 비방송 연습이 시작되네요...\n\n'
      '방송으로 뵙지 못해 허한 마음을 카드깡으로 시원하게 달래시라고, 20만 포인트를 직접 지급해 드렸습니다!\n\n'
      '(※ 본 20만 포인트는 우편 수령 버튼을 누르실 필요 없이 이미 보유 포인트에 즉시 추가되었습니다!)\n\n'
      '다들 득템하시길 바랍니다! 🃏✨',
      'SYSTEM',
      0
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_unbroadcasted_practice_reward_20260805
  from public, anon, authenticated;

commit;
