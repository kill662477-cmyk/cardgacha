-- 사료 금단현상 극복 긴급 10만포인트 지급

begin;

create table if not exists public.gacha_s2_withdrawal_symptoms_reward_20260804 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz not null default now()
);

insert into public.gacha_s2_withdrawal_symptoms_reward_20260804 (user_id)
select id from public.gacha_s2_accounts
on conflict (user_id) do nothing;

update public.gacha_s2_withdrawal_symptoms_reward_20260804
set granted = true, granted_at = now()
where granted = false;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id from public.gacha_s2_withdrawal_symptoms_reward_20260804
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'withdrawal-symptoms-reward-20260804',
      '[이벤트] 사료 금단현상 극복 기원 긴급 처방전! 💊',
      E'"아... 사료 금단현상 너무 힘드네요..."\n\n'
      '최근 사료 지급 중단 선언 이후, 곳곳에서 금단현상을 호소하시는 분들이 속출하고 있습니다! 😭\n'
      '차마 그 모습을 지켜볼 수 없어 긴급 처방전으로 10만 포인트를 준비했습니다.\n\n'
      '이걸로 잠시나마 금단현상을 이겨내시고 즐거운 카드가챠 되시길 바랍니다! 💖\n'
      '10만 포인트 먹고 갑시다!!',
      'REWARD',
      100000
    );
  end loop;
end
$mail$;

revoke all on table public.gacha_s2_withdrawal_symptoms_reward_20260804
  from public, anon, authenticated;

commit;
