-- Reconcile both sender-side and recipient-side SOOP rewards to 30P per balloon.
-- Window: 2026-07-22 00:00 through 2026-07-22 23:59:59 KST.
-- Accountless sides are excluded. Sides already paid at least 30P receive no adjustment.

begin;

create table if not exists public.gacha_s2_donation_30x_reconciliation_20260722 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  sender_event_count integer not null check (sender_event_count >= 0),
  recipient_event_count integer not null check (recipient_event_count >= 0),
  balloon_side_amount bigint not null check (balloon_side_amount > 0),
  points_already_received bigint not null check (points_already_received >= 0),
  target_points bigint not null check (target_points = balloon_side_amount * 30),
  points_granted integer not null check (points_granted > 0),
  points_before integer not null,
  points_after integer,
  granted_at timestamptz not null default now()
);

with eligible_sides as (
  select
    event.event_id,
    'sender'::text as reward_side,
    account.id as user_id,
    event.amount,
    case when event.sender_user_id = account.id then event.points_per_account else 0 end as received_points
  from public.gacha_s2_soop_donation_events event
  join public.gacha_s2_accounts account on account.soop_id = event.sender_soop_id
  join public.gacha_s2_player_states state on state.user_id = account.id
  where event.created_at >= timestamptz '2026-07-21 15:00:00+00'
    and event.created_at < timestamptz '2026-07-22 15:00:00+00'

  union all

  select
    event.event_id,
    'recipient'::text as reward_side,
    account.id as user_id,
    event.amount,
    case when event.recipient_user_id = account.id then event.points_per_account else 0 end as received_points
  from public.gacha_s2_soop_donation_events event
  join public.gacha_s2_accounts account on account.soop_id = event.recipient_soop_id
  join public.gacha_s2_player_states state on state.user_id = account.id
  where event.created_at >= timestamptz '2026-07-21 15:00:00+00'
    and event.created_at < timestamptz '2026-07-22 15:00:00+00'
), grouped as (
  select
    user_id,
    count(*) filter (where reward_side = 'sender')::integer as sender_event_count,
    count(*) filter (where reward_side = 'recipient')::integer as recipient_event_count,
    sum(amount)::bigint as balloon_side_amount,
    sum(received_points)::bigint as points_already_received,
    sum(amount::bigint * 30)::bigint as target_points,
    sum(greatest(amount * 30 - received_points, 0))::integer as points_granted
  from eligible_sides
  group by user_id
  having sum(greatest(amount * 30 - received_points, 0)) > 0
)
insert into public.gacha_s2_donation_30x_reconciliation_20260722 (
  user_id,
  sender_event_count,
  recipient_event_count,
  balloon_side_amount,
  points_already_received,
  target_points,
  points_granted,
  points_before
)
select
  grouped.user_id,
  grouped.sender_event_count,
  grouped.recipient_event_count,
  grouped.balloon_side_amount,
  grouped.points_already_received,
  grouped.target_points,
  grouped.points_granted,
  state.points
from grouped
join public.gacha_s2_player_states state on state.user_id = grouped.user_id
on conflict (user_id) do nothing;

update public.gacha_s2_player_states state
set points = state.points + reconciliation.points_granted,
    revision = state.revision + 1,
    updated_at = now()
from public.gacha_s2_donation_30x_reconciliation_20260722 reconciliation
where state.user_id = reconciliation.user_id
  and reconciliation.points_after is null;

update public.gacha_s2_donation_30x_reconciliation_20260722 reconciliation
set points_after = state.points
from public.gacha_s2_player_states state
where state.user_id = reconciliation.user_id
  and reconciliation.points_after is null;

do $$
declare
  v_expected_targets integer;
  v_expected_grant bigint;
begin
  with eligible_sides as (
    select
      account.id as user_id,
      event.amount,
      case when event.sender_user_id = account.id then event.points_per_account else 0 end as received_points
    from public.gacha_s2_soop_donation_events event
    join public.gacha_s2_accounts account on account.soop_id = event.sender_soop_id
    join public.gacha_s2_player_states state on state.user_id = account.id
    where event.created_at >= timestamptz '2026-07-21 15:00:00+00'
      and event.created_at < timestamptz '2026-07-22 15:00:00+00'

    union all

    select
      account.id as user_id,
      event.amount,
      case when event.recipient_user_id = account.id then event.points_per_account else 0 end as received_points
    from public.gacha_s2_soop_donation_events event
    join public.gacha_s2_accounts account on account.soop_id = event.recipient_soop_id
    join public.gacha_s2_player_states state on state.user_id = account.id
    where event.created_at >= timestamptz '2026-07-21 15:00:00+00'
      and event.created_at < timestamptz '2026-07-22 15:00:00+00'
  ), grouped as (
    select
      user_id,
      sum(greatest(amount * 30 - received_points, 0))::bigint as points_granted
    from eligible_sides
    group by user_id
    having sum(greatest(amount * 30 - received_points, 0)) > 0
  )
  select count(*)::integer, coalesce(sum(points_granted), 0)::bigint
  into v_expected_targets, v_expected_grant
  from grouped;

  if (
    select count(*)
    from public.gacha_s2_donation_30x_reconciliation_20260722
  ) <> v_expected_targets then
    raise exception '20260722 donation reconciliation target count mismatch';
  end if;

  if (
    select coalesce(sum(points_granted), 0)
    from public.gacha_s2_donation_30x_reconciliation_20260722
  ) <> v_expected_grant then
    raise exception '20260722 donation reconciliation grant total mismatch';
  end if;

  if exists (
    select 1
    from public.gacha_s2_donation_30x_reconciliation_20260722 reconciliation
    where reconciliation.points_after is null
       or reconciliation.points_after <> reconciliation.points_before + reconciliation.points_granted
  ) then
    raise exception '20260722 donation reconciliation amount validation failed';
  end if;
end;
$$;

revoke all on table public.gacha_s2_donation_30x_reconciliation_20260722
  from public, anon, authenticated;

commit;
