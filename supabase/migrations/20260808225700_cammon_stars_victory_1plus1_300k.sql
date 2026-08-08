-- 캄몬스타즈 5:2 개막전 승리 기념 1+1 보너스 30만 포인트 다이렉트 지급 및 안내

begin;

create table if not exists public.gacha_s2_cammon_stars_victory_1plus1_20260808 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_cammon_stars_victory_1plus1_20260808 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_cammon_stars_victory_1plus1_20260808 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 300000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_cammon_stars_victory_1plus1_20260808
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_cammon_stars_victory_1plus1_20260808
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'cammon-stars-victory-1plus1-300k-20260808',
      '🌟 [1+1 이벤트] K-중만컵 개막전 캄몬스타즈 승리 기념 보너스 축하금! 🌟',
      E'끝난 줄 아셨죠?! 😎\n\n'
      'K-중만컵 개막전 캄몬스타즈의 멋진 5:2 승리를 다시 한번 기념하며,\n'
      '기쁨을 ✌️두 배✌️로 나누기 위해 1+1 이벤트를 발동합니다!\n\n'
      '🎇 보너스 축하금 300,000 포인트를 추가로 즉시 꽂아드렸습니다! 🎇\n\n'
      '(※ 본 30만 포인트 역시 우편 수령 버튼을 누르실 필요 없이 이미 보유 포인트에 다이렉트로 즉시 충전되었습니다.)\n\n'
      '오늘 밤은 카드깡 파티입니다!! 🥳\n'
      '다시 한번 캄몬스타즈 V2 가즈아~~!! 🏆✨\n\n'
      '🎊✨🎊✨🎊✨🎊✨🎊✨🎊✨',
      'SYSTEM',
      0
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_cammon_stars_victory_1plus1_20260808
  from public, anon, authenticated;

commit;
