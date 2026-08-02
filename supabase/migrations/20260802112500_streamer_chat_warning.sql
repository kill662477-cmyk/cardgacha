-- 스트리머 방송 방해 1차 경고 안내 및 10만 포인트 지급

begin;

create table if not exists public.gacha_s2_streamer_chat_warning_20260802 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_streamer_chat_warning_20260802 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_streamer_chat_warning_20260802 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 100000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_streamer_chat_warning_20260802
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_streamer_chat_warning_20260802
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'streamer-chat-warning-20260802',
      '[공지] 스트리머 방송 관련 1차 경고 안내',
      E'스트리머 방송에서 카드가챠 관련 멘트로 방송 방해하시는 분은 계정 삭제 조치하도록 하겠습니다.\n\n'
      '본 안내는 전체 유저를 대상으로 발송되는 1차 경고입니다. 캄몬스타즈와 관련된 언급으로 타 스트리머 분들의 방송에 피해가 가지 않도록 유의해 주시기 바랍니다.\n\n'
      '안내 우편과 함께 10만 포인트를 지급해 드립니다.',
      'REWARD',
      100000
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_streamer_chat_warning_20260802
  from public, anon, authenticated;

commit;
