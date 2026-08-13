-- 캄스증권 23시 틱 충돌 오류 안내 및 20만 포인트 다이렉트 지급

begin;

create table if not exists public.gacha_s2_cams_stock_error_reward_20260813 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_cams_stock_error_reward_20260813 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_cams_stock_error_reward_20260813 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 200000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_cams_stock_error_reward_20260813
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_cams_stock_error_reward_20260813
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'cams-stock-error-200k-20260813',
      '⚠️ [안내] 캄스증권 23시 틱 반영 오류 안내 및 보상 지급 ⚠️',
      E'안녕하세요. 캄몬스타즈입니다.\n\n'
      '현재 캄스증권 랜덤 틱 생성 과정에서 소수점 초과 문제로 인해\n'
      '23시 틱이 정상적으로 반영되지 않고 충돌이 발생하는 현상이 확인되었습니다. 😭\n\n'
      '해당 문제는 소수점 값을 수정하여 곧 정상 반영될 예정이오니, 투자에 참고 부탁드립니다!\n\n'
      '게임 이용에 불편을 드려 죄송한 마음을 담아,\n'
      '전 계정에 사과 보상 200,000 포인트를 지급해 드렸습니다. 🙇‍♂️\n\n'
      '(※ 본 20만 포인트는 우편 수령 버튼을 누르실 필요 없이 이미 보유 포인트에 다이렉트로 즉시 충전되었습니다.)\n\n'
      '빠르게 수정하여 원활한 투자가 이루어질 수 있도록 조치하겠습니다.\n'
      '감사합니다.',
      'SYSTEM',
      0
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_cams_stock_error_reward_20260813
  from public, anon, authenticated;

commit;
