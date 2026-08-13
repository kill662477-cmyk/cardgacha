-- 카드 가챠 시즌2 서비스 종료 안내 우편 발송

begin;

create table if not exists public.gacha_s2_season2_shutdown_notice_20260814 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_season2_shutdown_notice_20260814 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_season2_shutdown_notice_20260814 where granted = false
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'season2-shutdown-notice-20260814',
      '📢 [중요] 카드 가챠 시즌2 서비스 종료 사전 안내 📢',
      E'안녕하세요. 캄몬스타즈입니다.\n\n'
      '그동안 <카드 가챠 시즌2>를 이용해 주시고 아껴주신 모든 유저 여러분께 진심으로 깊은 감사의 말씀을 드립니다. 🙇‍♂️\n\n'
      '아쉬운 소식을 전해드리게 되어 마음이 무겁지만,\n'
      '<카드 가챠 시즌2>는 오는 🗓️ 2026년 8월 21일 🗓️을 마지막으로 서비스가 종료될 예정입니다.\n\n'
      '오픈부터 지금까지 여러분과 함께 만들어온 소중한 추억들은 저희 팀 모두의 가슴 속에 깊이 간직하겠습니다. ✨\n\n'
      '마지막 서비스 종료 시점까지 게임 이용에 불편함이 없으시도록 최선을 다하겠으며, 남은 기간 동안 편안하고 즐거운 시간 보내시기를 바랍니다.\n\n'
      '다시 한번 그동안 보내주신 넘치는 사랑과 성원에 감사드립니다.\n\n'
      '- 캄몬스타즈 개발/운영진 일동 올림 -',
      'SYSTEM',
      0
    );
  end loop;
end
$mail$;

update public.gacha_s2_season2_shutdown_notice_20260814
set granted = true, granted_at = now()
where granted = false;

revoke all on table public.gacha_s2_season2_shutdown_notice_20260814
  from public, anon, authenticated;

commit;
