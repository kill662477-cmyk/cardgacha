-- 간바레 이벤트 형평성 보상 (전투력 100만 이상 유저 25만 포인트)

begin;

create table if not exists public.gacha_s2_compensation_1m_plus_20260802 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

-- 전투력 100만 이상인 유저만 타겟팅
insert into public.gacha_s2_compensation_1m_plus_20260802 (user_id)
select s.user_id 
from public.gacha_s2_player_states s
where coalesce(s.power_snapshot, 0) >= 1000000
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_compensation_1m_plus_20260802 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 250000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_compensation_1m_plus_20260802
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_compensation_1m_plus_20260802
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'compensation-1m-plus-event-20260802',
      '[안내] 간바레 이벤트 관련 추가 지급 안내',
      E'간바레 이벤트 보상 지급 과정에서 기준 이슈가 발생하여, 전투력 100만 이상 유저분들께 추가 보상으로 25만 포인트를 지급해 드립니다.\n\n'
      '혼선을 드려 진심으로 죄송합니다.',
      'REWARD',
      250000
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_compensation_1m_plus_20260802
  from public, anon, authenticated;

commit;
