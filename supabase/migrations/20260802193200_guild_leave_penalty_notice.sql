-- 길드 탈퇴 페널티 복구 중단 공지 및 10만 포인트 지급

begin;

create table if not exists public.gacha_s2_guild_leave_penalty_notice_20260802 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_guild_leave_penalty_notice_20260802 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_guild_leave_penalty_notice_20260802 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 100000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_guild_leave_penalty_notice_20260802
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_guild_leave_penalty_notice_20260802
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'guild-leave-penalty-notice-20260802',
      '[안내] 길드 탈퇴 페널티 복구 중단 공지',
      E'이제 더이상 길드 탈퇴 페널티 안풀어 드립니다. 다른길드 만들어진다고 옮기실분은 그냥 미리 길드 탈퇴 해놔주세요\n'
      '다시한번 말씀드립니다. 길드 탈퇴 페널티 이제 안풀어 드립니다.\n\n'
      '안내와 함께 10만 포인트를 지급해 드립니다.',
      'SYSTEM',
      100000
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_guild_leave_penalty_notice_20260802
  from public, anon, authenticated;

commit;
