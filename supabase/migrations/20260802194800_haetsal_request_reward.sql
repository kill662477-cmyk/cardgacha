-- 햇살님 특별 요청 전체 10만 포인트 지급 및 안내

begin;

create table if not exists public.gacha_s2_haetsal_request_reward_20260802 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_haetsal_request_reward_20260802 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_haetsal_request_reward_20260802 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 100000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_haetsal_request_reward_20260802
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_haetsal_request_reward_20260802
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'haetsal-request-reward-20260802',
      '[안내] 햇살님의 특별 요청 기념 10만 포인트 지급',
      E'햇살님의 특별 요청으로 전체 계정에 10만 포인트를 지급해 드립니다!\n\n'
      '첨부된 포인트를 수령해 주세요.',
      'REWARD',
      100000
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_haetsal_request_reward_20260802
  from public, anon, authenticated;

commit;
