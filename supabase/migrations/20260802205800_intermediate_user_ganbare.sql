-- 중수 유저 간바레 이벤트 25만 포인트 지급 (전투력 120만 미만)

begin;

create table if not exists public.gacha_s2_mid_user_ganbare_20260802 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

-- 전투력 120만 미만인 유저만 타겟팅 (새로 삽입)
insert into public.gacha_s2_mid_user_ganbare_20260802 (user_id)
select s.user_id 
from public.gacha_s2_player_states s
where coalesce(s.power_snapshot, 0) < 1200000
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_mid_user_ganbare_20260802 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 250000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_mid_user_ganbare_20260802
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_mid_user_ganbare_20260802
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'mid-user-ganbare-event-20260802',
      '[이벤트] 중수 유저분들 간바레 이벤트! 25만 포인트 지급',
      E'전투력 120만 미만 중수 유저분들을 위한 간바레 이벤트입니다!\n\n'
      '첨부된 25만 포인트를 수령하시고 더 높은 곳을 향해 힘차게 도전해 보세요!',
      'EVENT',
      250000
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_mid_user_ganbare_20260802
  from public, anon, authenticated;

commit;
