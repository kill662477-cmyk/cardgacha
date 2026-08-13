-- Grant every current account 500,000P for the market floor incident.
-- Any corrected recovery balance is automatically offset by the existing points trigger.

lock table public.gacha_s2_player_states in share row exclusive mode;

create table if not exists public.gacha_s2_market_bug_compensation_20260813 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  points_before integer not null check (points_before >= 0),
  gross_reward integer not null default 500000 check (gross_reward = 500000),
  outstanding_before bigint not null default 0 check (outstanding_before >= 0),
  outstanding_after bigint check (outstanding_after >= 0),
  offset_applied bigint check (offset_applied between 0 and 500000),
  net_credited integer check (net_credited between 0 and 500000),
  points_after integer check (points_after >= 0),
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  constraint gacha_s2_market_bug_compensation_balance_check check (
    applied_at is null
    or (
      outstanding_after is not null
      and offset_applied is not null
      and net_credited is not null
      and points_after is not null
      and offset_applied + net_credited = gross_reward
      and points_after = points_before + net_credited
      and outstanding_before - outstanding_after = offset_applied
    )
  )
);

alter table public.gacha_s2_market_bug_compensation_20260813 enable row level security;
revoke all on table public.gacha_s2_market_bug_compensation_20260813
  from public, anon, authenticated;
grant select on table public.gacha_s2_market_bug_compensation_20260813 to service_role;

insert into public.gacha_s2_market_bug_compensation_20260813 (
  user_id,
  points_before,
  outstanding_before
)
select state.user_id,
       state.points,
       coalesce(correction.outstanding_points, 0)
from public.gacha_s2_player_states state
left join public.gacha_s2_market_floor_recovery_corrections correction
  on correction.operation_key = 'market-100p-floor-recovery-correction-20260813'
 and correction.user_id = state.user_id
on conflict (user_id) do nothing;

update public.gacha_s2_player_states state
set points = state.points + reward.gross_reward,
    revision = state.revision + 1,
    updated_at = now()
from public.gacha_s2_market_bug_compensation_20260813 reward
where state.user_id = reward.user_id
  and reward.applied_at is null;

update public.gacha_s2_market_bug_compensation_20260813 reward
set outstanding_after = coalesce(correction.outstanding_points, 0),
    offset_applied = reward.outstanding_before - coalesce(correction.outstanding_points, 0),
    net_credited = state.points - reward.points_before,
    points_after = state.points,
    applied_at = now()
from public.gacha_s2_player_states state
left join public.gacha_s2_market_floor_recovery_corrections correction
  on correction.operation_key = 'market-100p-floor-recovery-correction-20260813'
 and correction.user_id = state.user_id
where state.user_id = reward.user_id
  and reward.applied_at is null;

insert into public.gacha_s2_mailbox (
  user_id, event_key, category, title, body, points
)
select reward.user_id,
       'market-bug-global-compensation-500k-20260813',
       'REWARD',
       '[보상] 캄스증권 오류 보상 500,000P 지급',
       case
         when reward.offset_applied > 0 then
           '캄스증권 파생상품 가격 하한 오류와 회수 기준 정정으로 불편을 드린 점에 대한 보상으로 '
           || '전 계정 500,000P를 지급했습니다. '
           || '정정된 회수 잔액 ' || reward.offset_applied || 'P가 이번 지급액에서 자동 상계되어, '
           || '실제 보유 포인트에는 ' || reward.net_credited || 'P가 반영되었습니다. '
           || '현재 남은 상계액은 ' || reward.outstanding_after || 'P입니다.'
         else
           '캄스증권 파생상품 가격 하한 오류와 회수 기준 정정으로 불편을 드린 점에 대한 보상으로 '
           || '전 계정 500,000P를 지급했습니다. 보유 포인트에 500,000P가 반영되었습니다.'
       end,
       0
from public.gacha_s2_market_bug_compensation_20260813 reward
on conflict (user_id, event_key) do nothing;

do $verify$
declare
  v_player_count integer;
  v_reward_count integer;
  v_reward_total bigint;
  v_mail_count integer;
begin
  select count(*)::integer into v_player_count
  from public.gacha_s2_player_states;

  select count(*)::integer, coalesce(sum(gross_reward), 0)::bigint
  into v_reward_count, v_reward_total
  from public.gacha_s2_market_bug_compensation_20260813;

  if v_reward_count <> v_player_count then
    raise exception 'MARKET_BUG_COMPENSATION_TARGET_COUNT_MISMATCH';
  end if;

  if v_reward_total <> v_reward_count::bigint * 500000 then
    raise exception 'MARKET_BUG_COMPENSATION_TOTAL_MISMATCH';
  end if;

  if exists (
    select 1
    from public.gacha_s2_market_bug_compensation_20260813
    where applied_at is null
       or offset_applied + net_credited <> gross_reward
       or points_after <> points_before + net_credited
       or outstanding_before - outstanding_after <> offset_applied
  ) then
    raise exception 'MARKET_BUG_COMPENSATION_BALANCE_MISMATCH';
  end if;

  select count(*)::integer into v_mail_count
  from public.gacha_s2_mailbox
  where event_key = 'market-bug-global-compensation-500k-20260813';

  if v_mail_count <> v_reward_count then
    raise exception 'MARKET_BUG_COMPENSATION_MAIL_COUNT_MISMATCH';
  end if;

  if exists (select 1 from public.gacha_s2_player_states where points < 0) then
    raise exception 'MARKET_BUG_COMPENSATION_NEGATIVE_POINTS';
  end if;
end
$verify$;
