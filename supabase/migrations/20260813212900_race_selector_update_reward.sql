-- 종족선택변경권 업데이트 기념 30만 포인트 다이렉트 지급 및 안내

begin;

create table if not exists public.gacha_s2_race_selector_update_reward_20260813 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_race_selector_update_reward_20260813 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_race_selector_update_reward_20260813 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 300000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_race_selector_update_reward_20260813
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_race_selector_update_reward_20260813
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'race-selector-update-300k-20260813',
      '🎉 [업데이트 기념] 신규 아이템 ''종족선택변경권'' 추가 및 30만 포인트 지급! 🎉',
      E'✨ 신규 아이템 ''종족선택변경권''이 업데이트 되었습니다! ✨\n\n'
      '나만의 덱을 완성해보세요! 🃏\n\n'
      '엄청 비싸죠? 😅\n'
      '''캄스증권''을 통해서 열심히 벌어보세요! ㅋㅋㅋ 📈💸\n\n'
      '업데이트를 기념하여 전 계정에 300,000 포인트를 쏘아드렸습니다! 🚀\n\n'
      '(※ 본 30만 포인트는 우편 수령 버튼을 누르실 필요 없이 이미 보유 포인트에 다이렉트로 즉시 충전되었습니다.)\n\n'
      '성공적인 투자와 완벽한 덱 세팅을 기원합니다! 🏆✨',
      'SYSTEM',
      0
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_race_selector_update_reward_20260813
  from public, anon, authenticated;

commit;
