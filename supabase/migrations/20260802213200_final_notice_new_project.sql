-- 향후 업데이트 및 신작 프로젝트 안내 공지 (포인트 지급 없음)

begin;

create table if not exists public.gacha_s2_final_notice_new_project_20260802 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_final_notice_new_project_20260802 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

update public.gacha_s2_final_notice_new_project_20260802
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_final_notice_new_project_20260802
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'final-notice-new-project-20260802',
      '[안내] 향후 업데이트 및 신작 프로젝트 관련 안내 📢',
      E'마지막 사료, 달달하셨나요? 🎁\n\n'
      '이제 \'K-중만컵 승리 기념\' 외에는 당분간 사료(포인트) 지급이 없을 예정입니다.\n\n'
      '현재 카드가챠를 보조하고 있는 AI 에이전트들은 모두 \'리니지 라이크 MMORPG\' 컨셉의 차기작 제작에 전면 투입될 예정입니다. '
      '신작 개발에 상당히 오랜 기간이 소요될 것으로 예상되오니, 현재 진행 중인 카드가챠 시즌 종료는 당분간 전혀 걱정하지 않으셔도 좋습니다! 😆\n\n'
      '다들 다가오는 K-중만컵을 신나게 즐기시면서, 저희 카드가챠와도 계속해서 즐거운 시간 보내주시길 바랍니다.\n\n'
      '항상 감사드립니다! 💖',
      'SYSTEM',
      0
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_final_notice_new_project_20260802
  from public, anon, authenticated;

commit;
