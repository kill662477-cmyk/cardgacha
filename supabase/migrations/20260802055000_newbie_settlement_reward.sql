-- 어제 신규 가입자 뉴비 정착금 50만 포인트 지급 (2026-08-01 가입자 대상)

begin;

create table if not exists public.gacha_s2_newbie_settlement_20260802 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_newbie_settlement_20260802 (user_id)
select id from public.gacha_s2_accounts
where created_at >= '2026-08-01 00:00:00+09'::timestamptz
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_newbie_settlement_20260802 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 500000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_newbie_settlement_20260802
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_newbie_settlement_20260802
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'newbie-settlement-reward-20260802',
      '[선물] 🌱 캄몬스타즈 신규 가입 정착금 500,000 P 지급 🌱',
      E'반갑습니다! 최근 캄몬스타즈에 새로 합류하신 신규 유저분들을 진심으로 환영합니다!\n\n'
      '여러분의 즐거운 캄몬스타즈 라이프와 원활한 초기 정착을 응원하며 50만 포인트를 정착금으로 준비했습니다!\n'
      '멋진 카드들을 모으고 팀을 성장시키며 캄몬스타즈와 함께 즐거운 시간 보내시길 바랍니다. 캄몬!',
      'REWARD',
      500000
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_newbie_settlement_20260802
  from public, anon, authenticated;

commit;
