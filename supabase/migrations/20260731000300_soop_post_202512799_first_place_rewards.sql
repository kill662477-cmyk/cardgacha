-- SOOP post 202512799 first-place celebration rewards.
-- Reward population: every Season 2 account with a player state.
-- High tier: event-authenticated OR streamer OR API donation sender.
-- Standard tier: every remaining prepared account.

begin;

lock table public.gacha_s2_accounts in share mode;
lock table public.gacha_s2_player_states in share row exclusive mode;
lock table public.gacha_s2_soop_post_202512799_rewards in share mode;
lock table public.gacha_s2_soop_donation_events in share mode;
lock table public.gacha_s2_mailbox in share row exclusive mode;

create table if not exists public.gacha_s2_soop_post_202512799_first_place_rewards (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete restrict,
  tier text not null check (tier in ('HIGH', 'STANDARD')),
  event_authenticated boolean not null,
  streamer boolean not null,
  api_donor boolean not null,
  points_before integer not null,
  ss_selector_before integer not null check (ss_selector_before >= 0),
  sss_selector_before integer not null check (sss_selector_before >= 0),
  points_granted integer not null,
  ss_selector_granted integer not null,
  sss_selector_granted integer not null,
  points_after integer,
  ss_selector_after integer,
  sss_selector_after integer,
  granted_at timestamptz not null default now(),
  check (
    (tier = 'HIGH'
      and points_granted = 100000
      and ss_selector_granted = 1
      and sss_selector_granted = 1)
    or
    (tier = 'STANDARD'
      and points_granted = 50000
      and ss_selector_granted = 1
      and sss_selector_granted = 0)
  ),
  check (
    (tier = 'HIGH' and (event_authenticated or streamer or api_donor))
    or tier = 'STANDARD'
  )
);

alter table public.gacha_s2_soop_post_202512799_first_place_rewards
  enable row level security;

revoke all on table public.gacha_s2_soop_post_202512799_first_place_rewards
  from public, anon, authenticated;
grant select, insert, update
  on table public.gacha_s2_soop_post_202512799_first_place_rewards
  to service_role;

create temporary table soop_post_202512799_first_place_targets (
  user_id uuid primary key,
  soop_id text not null,
  game_nickname text not null,
  tier text not null,
  event_authenticated boolean not null,
  streamer boolean not null,
  api_donor boolean not null,
  points_before integer not null,
  ss_selector_before integer not null,
  sss_selector_before integer not null,
  points_granted integer not null,
  ss_selector_granted integer not null,
  sss_selector_granted integer not null
) on commit drop;

insert into soop_post_202512799_first_place_targets (
  user_id,
  soop_id,
  game_nickname,
  tier,
  event_authenticated,
  streamer,
  api_donor,
  points_before,
  ss_selector_before,
  sss_selector_before,
  points_granted,
  ss_selector_granted,
  sss_selector_granted
)
with classified as (
  select
    account.id as user_id,
    lower(trim(account.soop_id)) as soop_id,
    account.nickname as game_nickname,
    exists (
      select 1
      from public.gacha_s2_soop_post_202512799_rewards authenticated
      where authenticated.user_id = account.id
        and authenticated.source_post_id = 202512799
    ) as event_authenticated,
    account.is_streamer as streamer,
    exists (
      select 1
      from public.gacha_s2_soop_donation_events donation
      where donation.sender_user_id = account.id
        or lower(trim(donation.sender_soop_id)) = lower(trim(account.soop_id))
    ) as api_donor,
    state.points as points_before,
    (state.support_items->>'ssCardSelector')::integer as ss_selector_before,
    (state.support_items->>'sssCardSelector')::integer as sss_selector_before
  from public.gacha_s2_accounts account
  join public.gacha_s2_player_states state
    on state.user_id = account.id
)
select
  classified.user_id,
  classified.soop_id,
  classified.game_nickname,
  case
    when classified.event_authenticated
      or classified.streamer
      or classified.api_donor
    then 'HIGH'
    else 'STANDARD'
  end,
  classified.event_authenticated,
  classified.streamer,
  classified.api_donor,
  classified.points_before,
  classified.ss_selector_before,
  classified.sss_selector_before,
  case
    when classified.event_authenticated
      or classified.streamer
      or classified.api_donor
    then 100000
    else 50000
  end,
  1,
  case
    when classified.event_authenticated
      or classified.streamer
      or classified.api_donor
    then 1
    else 0
  end
from classified;

do $preflight$
declare
  v_target_count integer;
  v_unique_user_count integer;
  v_high_count integer;
  v_standard_count integer;
  v_authenticated_count integer;
  v_streamer_count integer;
  v_api_donor_count integer;
  v_points_total bigint;
  v_ss_total bigint;
  v_sss_total bigint;
  v_invalid_inventory_count integer;
  v_existing_reward_count integer;
  v_existing_mail_count integer;
begin
  select
    count(*),
    count(distinct user_id),
    count(*) filter (where tier = 'HIGH'),
    count(*) filter (where tier = 'STANDARD'),
    count(*) filter (where event_authenticated),
    count(*) filter (where streamer),
    count(*) filter (where api_donor),
    coalesce(sum(points_granted), 0),
    coalesce(sum(ss_selector_granted), 0),
    coalesce(sum(sss_selector_granted), 0),
    count(*) filter (
      where ss_selector_before < 0
        or sss_selector_before < 0
    )
  into
    v_target_count,
    v_unique_user_count,
    v_high_count,
    v_standard_count,
    v_authenticated_count,
    v_streamer_count,
    v_api_donor_count,
    v_points_total,
    v_ss_total,
    v_sss_total,
    v_invalid_inventory_count
  from soop_post_202512799_first_place_targets;

  select count(*)
  into v_existing_reward_count
  from public.gacha_s2_soop_post_202512799_first_place_rewards;

  select count(*)
  into v_existing_mail_count
  from public.gacha_s2_mailbox
  where event_key = 'soop-post-202512799:first-place-reward';

  if v_target_count <> 2167 or v_unique_user_count <> 2167 then
    raise exception
      'first-place target mismatch: targets %, unique users %',
      v_target_count,
      v_unique_user_count;
  end if;

  if v_high_count <> 248 or v_standard_count <> 1919 then
    raise exception
      'first-place tier mismatch: high %, standard %',
      v_high_count,
      v_standard_count;
  end if;

  if v_authenticated_count <> 124
    or v_streamer_count <> 22
    or v_api_donor_count <> 142 then
    raise exception
      'first-place source mismatch: authenticated %, streamer %, API donor %',
      v_authenticated_count,
      v_streamer_count,
      v_api_donor_count;
  end if;

  if v_points_total <> 120750000
    or v_ss_total <> 2167
    or v_sss_total <> 248 then
    raise exception
      'first-place reward total mismatch: points %, SS %, SSS %',
      v_points_total,
      v_ss_total,
      v_sss_total;
  end if;

  if v_invalid_inventory_count <> 0 then
    raise exception
      'first-place invalid selector inventory: %',
      v_invalid_inventory_count;
  end if;

  if v_existing_reward_count <> v_existing_mail_count
    or v_existing_reward_count not in (0, 2167) then
    raise exception
      'first-place partial prior state: rewards %, mails %',
      v_existing_reward_count,
      v_existing_mail_count;
  end if;
end
$preflight$;

create temporary table soop_post_202512799_first_place_awarded (
  user_id uuid primary key,
  tier text not null,
  points_before integer not null,
  ss_selector_before integer not null,
  sss_selector_before integer not null,
  points_granted integer not null,
  ss_selector_granted integer not null,
  sss_selector_granted integer not null
) on commit drop;

with inserted as (
  insert into public.gacha_s2_soop_post_202512799_first_place_rewards (
    user_id,
    tier,
    event_authenticated,
    streamer,
    api_donor,
    points_before,
    ss_selector_before,
    sss_selector_before,
    points_granted,
    ss_selector_granted,
    sss_selector_granted
  )
  select
    target.user_id,
    target.tier,
    target.event_authenticated,
    target.streamer,
    target.api_donor,
    target.points_before,
    target.ss_selector_before,
    target.sss_selector_before,
    target.points_granted,
    target.ss_selector_granted,
    target.sss_selector_granted
  from soop_post_202512799_first_place_targets target
  on conflict (user_id) do nothing
  returning
    user_id,
    tier,
    points_before,
    ss_selector_before,
    sss_selector_before,
    points_granted,
    ss_selector_granted,
    sss_selector_granted
)
insert into soop_post_202512799_first_place_awarded (
  user_id,
  tier,
  points_before,
  ss_selector_before,
  sss_selector_before,
  points_granted,
  ss_selector_granted,
  sss_selector_granted
)
select
  user_id,
  tier,
  points_before,
  ss_selector_before,
  sss_selector_before,
  points_granted,
  ss_selector_granted,
  sss_selector_granted
from inserted;

update public.gacha_s2_player_states state
set points = state.points + awarded.points_granted,
    support_items = jsonb_set(
      jsonb_set(
        state.support_items,
        '{ssCardSelector}',
        to_jsonb(
          coalesce((state.support_items->>'ssCardSelector')::integer, 0)
          + awarded.ss_selector_granted
        ),
        true
      ),
      '{sssCardSelector}',
      to_jsonb(
        coalesce((state.support_items->>'sssCardSelector')::integer, 0)
        + awarded.sss_selector_granted
      ),
      true
    ),
    revision = state.revision + 1,
    updated_at = now()
from soop_post_202512799_first_place_awarded awarded
where state.user_id = awarded.user_id;

update public.gacha_s2_soop_post_202512799_first_place_rewards reward
set points_after = state.points,
    ss_selector_after = (state.support_items->>'ssCardSelector')::integer,
    sss_selector_after = (state.support_items->>'sssCardSelector')::integer
from public.gacha_s2_player_states state
join soop_post_202512799_first_place_awarded awarded
  on awarded.user_id = state.user_id
where reward.user_id = awarded.user_id
  and reward.points_after is null;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
  v_body text;
begin
  for v_target in
    select user_id, tier, points_granted
    from soop_post_202512799_first_place_awarded
    order by user_id
  loop
    v_body := case v_target.tier
      when 'HIGH' then
        '투표 1등 달성 특별 보상으로 100,000 포인트, SSS 카드 선택권 1장, SS 카드 선택권 1장이 지급되었습니다.'
      else
        '투표 1등 달성 특별 보상으로 50,000 포인트와 SS 카드 선택권 1장이 지급되었습니다.'
    end;

    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'soop-post-202512799:first-place-reward',
      '[이벤트] 투표 1등 달성 특별 보상 지급 완료',
      v_body,
      'REWARD',
      v_target.points_granted
    );

    if v_mail_id is null then
      raise exception 'first-place mailbox creation failed';
    end if;
  end loop;
end
$mail$;

do $verify$
declare
  v_reward_count integer;
  v_high_count integer;
  v_standard_count integer;
  v_points_total bigint;
  v_ss_total bigint;
  v_sss_total bigint;
  v_delta_error_count integer;
  v_state_error_count integer;
  v_mail_count integer;
  v_mail_points_total bigint;
  v_mail_payload_error_count integer;
begin
  select
    count(*),
    count(*) filter (where tier = 'HIGH'),
    count(*) filter (where tier = 'STANDARD'),
    coalesce(sum(points_granted), 0),
    coalesce(sum(ss_selector_granted), 0),
    coalesce(sum(sss_selector_granted), 0),
    count(*) filter (
      where points_after <> points_before + points_granted
        or ss_selector_after <> ss_selector_before + ss_selector_granted
        or sss_selector_after <> sss_selector_before + sss_selector_granted
    )
  into
    v_reward_count,
    v_high_count,
    v_standard_count,
    v_points_total,
    v_ss_total,
    v_sss_total,
    v_delta_error_count
  from public.gacha_s2_soop_post_202512799_first_place_rewards;

  select count(*)
  into v_state_error_count
  from public.gacha_s2_soop_post_202512799_first_place_rewards reward
  join public.gacha_s2_player_states state
    on state.user_id = reward.user_id
  where state.points <> reward.points_after
    or (state.support_items->>'ssCardSelector')::integer
      <> reward.ss_selector_after
    or (state.support_items->>'sssCardSelector')::integer
      <> reward.sss_selector_after;

  select
    count(*),
    coalesce(sum(mail.points), 0),
    count(*) filter (
      where mail.title <> '[이벤트] 투표 1등 달성 특별 보상 지급 완료'
        or mail.category <> 'REWARD'
        or mail.points <> reward.points_granted
        or (
          reward.tier = 'HIGH'
          and mail.body <>
            '투표 1등 달성 특별 보상으로 100,000 포인트, SSS 카드 선택권 1장, SS 카드 선택권 1장이 지급되었습니다.'
        )
        or (
          reward.tier = 'STANDARD'
          and mail.body <>
            '투표 1등 달성 특별 보상으로 50,000 포인트와 SS 카드 선택권 1장이 지급되었습니다.'
        )
    )
  into
    v_mail_count,
    v_mail_points_total,
    v_mail_payload_error_count
  from public.gacha_s2_soop_post_202512799_first_place_rewards reward
  join public.gacha_s2_mailbox mail
    on mail.user_id = reward.user_id
   and mail.event_key = 'soop-post-202512799:first-place-reward';

  if v_reward_count <> 2167
    or v_high_count <> 248
    or v_standard_count <> 1919
    or v_points_total <> 120750000
    or v_ss_total <> 2167
    or v_sss_total <> 248 then
    raise exception
      'first-place reward verification failed: count %, high %, standard %, points %, SS %, SSS %',
      v_reward_count,
      v_high_count,
      v_standard_count,
      v_points_total,
      v_ss_total,
      v_sss_total;
  end if;

  if v_delta_error_count <> 0 or v_state_error_count <> 0 then
    raise exception
      'first-place state verification failed: deltas %, states %',
      v_delta_error_count,
      v_state_error_count;
  end if;

  if v_mail_count <> 2167
    or v_mail_points_total <> 120750000
    or v_mail_payload_error_count <> 0 then
    raise exception
      'first-place mailbox verification failed: count %, points %, payload errors %',
      v_mail_count,
      v_mail_points_total,
      v_mail_payload_error_count;
  end if;
end
$verify$;

commit;
