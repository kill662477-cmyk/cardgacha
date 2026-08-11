-- '캄스증권' 오픈 기념 20만 포인트 다이렉트 지급 및 안내

begin;

create table if not exists public.gacha_s2_cams_stock_open_reward_20260811 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_cams_stock_open_reward_20260811 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_cams_stock_open_reward_20260811 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 200000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_cams_stock_open_reward_20260811
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_cams_stock_open_reward_20260811
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'cams-stock-open-200k-20260811',
      '📈 [오픈 기념] 신규 미니게임 ''캄스증권'' 오픈! 시드머니 20만 포인트! 📈',
      E'📊 신규 미니게임 『캄스증권』 정식 오픈! 📊\n\n'
      '유저 여러분들의 성공적인 투자를 기원하며,\n'
      '초기 시드머니 200,000 포인트를 전 계정에 지원해 드립니다! 💸\n\n'
      '(※ 본 20만 포인트는 우편 수령 버튼을 누르실 필요 없이 이미 보유 포인트에 다이렉트로 즉시 충전되었습니다.)\n\n'
      '💡 [캄스증권 이용 안내] 💡\n'
      '🔹 매 정각(1시간마다) 주가가 새롭게 변동됩니다! (랜덤 등락)\n'
      '🔹 떡상할 종목을 예측해 포인트를 불려보세요!\n'
      '🔹 하지만 무리한 투자는 깡통 계좌의 지름길...😱\n\n'
      '야수의 심장으로 떡상을 노려보세요! 🚀\n'
      '유저 여러분들의 붉은 계좌를 열렬히 응원합니다! 📈✨',
      'SYSTEM',
      0
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_cams_stock_open_reward_20260811
  from public, anon, authenticated;

commit;
