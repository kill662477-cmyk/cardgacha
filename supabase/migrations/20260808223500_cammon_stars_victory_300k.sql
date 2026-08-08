-- 캄몬스타즈 5:2 승리 기념 30만 포인트 다이렉트 지급 및 축하 안내

begin;

create table if not exists public.gacha_s2_cammon_stars_victory_reward_20260808 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_cammon_stars_victory_reward_20260808 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

with pending_rewards as (
  select user_id from public.gacha_s2_cammon_stars_victory_reward_20260808 where granted = false
)
update public.gacha_s2_player_states state
set points = points + 300000,
    revision = revision + 1,
    updated_at = now()
from pending_rewards
where state.user_id = pending_rewards.user_id;

update public.gacha_s2_cammon_stars_victory_reward_20260808
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_cammon_stars_victory_reward_20260808
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'cammon-stars-victory-300k-20260808',
      '🌟 [축하] K-중만컵 캄몬스타즈 5:2 대승리 기념 특별 축하금! 🌟',
      E'🎊✨🎊✨🎊✨🎊✨🎊✨🎊✨\n\n'
      '🎉 K-중만컵 캄몬스타즈 VS 엠비대 🎉\n'
      '🔥 5 : 2 캄몬스타즈 압도적 승리!! 🔥\n\n'
      '캄몬스타즈의 눈부신 승리를 진심으로 축하합니다!\n'
      '승리의 기쁨을 모든 유저분들과 함께 나누기 위해,\n'
      '🎇 특별 축하금 300,000 포인트를 쏘아드렸습니다! 🎇\n\n'
      '(※ 본 30만 포인트는 우편 수령 버튼을 누르실 필요 없이 이미 보유 포인트에 즉시 추가되었습니다.)\n\n'
      '앞으로도 캄몬스타즈를 향한 뜨거운 응원 부탁드립니다!\n'
      '캄몬스타즈 V1 가즈아~~!! 🏆✨\n\n'
      '🎊✨🎊✨🎊✨🎊✨🎊✨🎊✨',
      'SYSTEM',
      0
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_cammon_stars_victory_reward_20260808
  from public, anon, authenticated;

commit;
