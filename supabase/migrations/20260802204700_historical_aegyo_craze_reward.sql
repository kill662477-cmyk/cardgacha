-- 사극 애교 열풍 기념 10만 포인트 지급 및 안내

begin;

create table if not exists public.gacha_s2_historical_aegyo_reward_20260802 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_historical_aegyo_reward_20260802 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_historical_aegyo_reward_20260802 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 100000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_historical_aegyo_reward_20260802
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_historical_aegyo_reward_20260802
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'historical-aegyo-reward-20260802',
      '[안내] 사극 애교 열풍, 잘 관람하였습니다! 🙇‍♂️',
      E'최근 불어온 사극 애교 열풍! 덕분에 즐겁게 잘 관람하였습니다.\n\n'
      '감사의 마음을 담아 모든 유저분들께 10만 포인트를 지급해 드립니다!\n\n'
      '앞으로도 카드가챠와 함께 즐거운 시간 보내시길 바랍니다. 💖',
      'REWARD',
      100000
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_historical_aegyo_reward_20260802
  from public, anon, authenticated;

commit;
