-- SOOP post 202512799 late image-authentication rewards.
-- The five accounts below commented with an image after the first-place payout.
-- Each already received the STANDARD first-place reward, so this migration:
--   1. grants the missing 50,000P participation reward; and
--   2. upgrades the first-place reward by 50,000P + one SSS selector.

begin;

set local statement_timeout = '5min';
set local lock_timeout = '60s';

create table if not exists
  public.gacha_s2_soop_post_202512799_first_place_reward_upgrades (
    user_id uuid primary key
      references public.gacha_s2_accounts(id) on delete restrict,
    soop_id text not null unique,
    source_post_id bigint not null default 202512799
      check (source_post_id = 202512799),
    points_before integer not null,
    sss_selector_before integer not null check (sss_selector_before >= 0),
    points_granted integer not null default 50000
      check (points_granted = 50000),
    sss_selector_granted integer not null default 1
      check (sss_selector_granted = 1),
    points_after integer,
    sss_selector_after integer,
    granted_at timestamptz not null default now()
  );

alter table
  public.gacha_s2_soop_post_202512799_first_place_reward_upgrades
  enable row level security;

revoke all on table
  public.gacha_s2_soop_post_202512799_first_place_reward_upgrades
  from public, anon, authenticated;

grant select, insert
  on table
    public.gacha_s2_soop_post_202512799_first_place_reward_upgrades
  to service_role;

create temporary table soop_post_202512799_late_auth_source (
  soop_id text primary key
) on commit drop;

insert into soop_post_202512799_late_auth_source (soop_id)
values
  ('taeryeong12'),
  ('rbals97'),
  ('juchi123'),
  ('qudgkr7275'),
  ('woduf1234');

create temporary table soop_post_202512799_late_auth_targets (
  user_id uuid primary key,
  soop_id text not null unique,
  game_nickname text not null,
  points_before integer not null,
  sss_selector_before integer not null,
  base_reward_exists boolean not null,
  final_tier text not null,
  upgrade_exists boolean not null
) on commit drop;

insert into soop_post_202512799_late_auth_targets (
  user_id,
  soop_id,
  game_nickname,
  points_before,
  sss_selector_before,
  base_reward_exists,
  final_tier,
  upgrade_exists
)
select
  account.id,
  lower(trim(account.soop_id)),
  account.nickname,
  state.points,
  coalesce((state.support_items->>'sssCardSelector')::integer, 0),
  base.user_id is not null,
  final.tier,
  upgrade.user_id is not null
from soop_post_202512799_late_auth_source source
join public.gacha_s2_accounts account
  on lower(trim(account.soop_id)) = source.soop_id
join public.gacha_s2_player_states state
  on state.user_id = account.id
join public.gacha_s2_soop_post_202512799_first_place_rewards final
  on final.user_id = account.id
left join public.gacha_s2_soop_post_202512799_rewards base
  on base.user_id = account.id
 and base.source_post_id = 202512799
left join
  public.gacha_s2_soop_post_202512799_first_place_reward_upgrades upgrade
  on upgrade.user_id = account.id
order by state.user_id
for update of state, final;

do $preflight$
declare
  v_source_count integer;
  v_target_count integer;
  v_unique_user_count integer;
  v_unique_soop_count integer;
  v_base_target_count integer;
  v_standard_target_count integer;
  v_high_target_count integer;
  v_upgrade_target_count integer;
  v_target_base_mail_count integer;
  v_target_original_final_mail_count integer;
  v_target_upgrade_mail_count integer;
  v_base_reward_count integer;
  v_base_reward_points bigint;
  v_base_mail_count integer;
  v_final_reward_count integer;
  v_final_high_count integer;
  v_final_standard_count integer;
  v_final_reward_points bigint;
  v_final_ss_total bigint;
  v_final_sss_total bigint;
  v_original_final_mail_count integer;
  v_upgrade_count integer;
  v_upgrade_mail_count integer;
begin
  select count(*)
  into v_source_count
  from soop_post_202512799_late_auth_source;

  select
    count(*),
    count(distinct user_id),
    count(distinct soop_id),
    count(*) filter (where base_reward_exists),
    count(*) filter (where final_tier = 'STANDARD'),
    count(*) filter (where final_tier = 'HIGH'),
    count(*) filter (where upgrade_exists)
  into
    v_target_count,
    v_unique_user_count,
    v_unique_soop_count,
    v_base_target_count,
    v_standard_target_count,
    v_high_target_count,
    v_upgrade_target_count
  from soop_post_202512799_late_auth_targets;

  select count(*)
  into v_target_base_mail_count
  from soop_post_202512799_late_auth_targets target
  join public.gacha_s2_mailbox mail
    on mail.user_id = target.user_id
   and mail.event_key = 'soop-post-202512799:reward-50k';

  select count(*)
  into v_target_original_final_mail_count
  from soop_post_202512799_late_auth_targets target
  join public.gacha_s2_mailbox mail
    on mail.user_id = target.user_id
   and mail.event_key = 'soop-post-202512799:first-place-reward';

  select count(*)
  into v_target_upgrade_mail_count
  from soop_post_202512799_late_auth_targets target
  join public.gacha_s2_mailbox mail
    on mail.user_id = target.user_id
   and mail.event_key =
     'soop-post-202512799:first-place-reward-upgrade';

  select count(*), coalesce(sum(points_granted), 0)
  into v_base_reward_count, v_base_reward_points
  from public.gacha_s2_soop_post_202512799_rewards
  where source_post_id = 202512799;

  select count(*)
  into v_base_mail_count
  from public.gacha_s2_mailbox
  where event_key = 'soop-post-202512799:reward-50k';

  select
    count(*),
    count(*) filter (where tier = 'HIGH'),
    count(*) filter (where tier = 'STANDARD'),
    coalesce(sum(points_granted), 0),
    coalesce(sum(ss_selector_granted), 0),
    coalesce(sum(sss_selector_granted), 0)
  into
    v_final_reward_count,
    v_final_high_count,
    v_final_standard_count,
    v_final_reward_points,
    v_final_ss_total,
    v_final_sss_total
  from public.gacha_s2_soop_post_202512799_first_place_rewards;

  select count(*)
  into v_original_final_mail_count
  from public.gacha_s2_mailbox
  where event_key = 'soop-post-202512799:first-place-reward';

  select count(*)
  into v_upgrade_count
  from
    public.gacha_s2_soop_post_202512799_first_place_reward_upgrades;

  select count(*)
  into v_upgrade_mail_count
  from public.gacha_s2_mailbox
  where event_key =
    'soop-post-202512799:first-place-reward-upgrade';

  if v_source_count <> 5
    or v_target_count <> 5
    or v_unique_user_count <> 5
    or v_unique_soop_count <> 5 then
    raise exception
      'late auth target mismatch: source %, targets %, users %, SOOP IDs %',
      v_source_count,
      v_target_count,
      v_unique_user_count,
      v_unique_soop_count;
  end if;

  if v_target_original_final_mail_count <> 5 then
    raise exception
      'late auth original final-mail mismatch: expected 5, actual %',
      v_target_original_final_mail_count;
  end if;

  if not (
    (
      v_base_target_count = 0
      and v_standard_target_count = 5
      and v_high_target_count = 0
      and v_upgrade_target_count = 0
      and v_target_base_mail_count = 0
      and v_target_upgrade_mail_count = 0
    )
    or
    (
      v_base_target_count = 5
      and v_standard_target_count = 0
      and v_high_target_count = 5
      and v_upgrade_target_count = 5
      and v_target_base_mail_count = 5
      and v_target_upgrade_mail_count = 5
    )
  ) then
    raise exception
      'late auth partial target state: base %, standard %, high %, upgrades %, base mails %, upgrade mails %',
      v_base_target_count,
      v_standard_target_count,
      v_high_target_count,
      v_upgrade_target_count,
      v_target_base_mail_count,
      v_target_upgrade_mail_count;
  end if;

  if not (
    (
      v_base_reward_count = 124
      and v_base_reward_points = 6200000
      and v_base_mail_count = 124
      and v_final_reward_count = 2167
      and v_final_high_count = 248
      and v_final_standard_count = 1919
      and v_final_reward_points = 120750000
      and v_final_ss_total = 2167
      and v_final_sss_total = 248
      and v_original_final_mail_count = 2167
      and v_upgrade_count = 0
      and v_upgrade_mail_count = 0
    )
    or
    (
      v_base_reward_count = 129
      and v_base_reward_points = 6450000
      and v_base_mail_count = 129
      and v_final_reward_count = 2167
      and v_final_high_count = 253
      and v_final_standard_count = 1914
      and v_final_reward_points = 121000000
      and v_final_ss_total = 2167
      and v_final_sss_total = 253
      and v_original_final_mail_count = 2167
      and v_upgrade_count = 5
      and v_upgrade_mail_count = 5
    )
  ) then
    raise exception
      'late auth global preflight mismatch: base %/%/%, final %/%/%/%/%/%, original mails %, upgrades %/%',
      v_base_reward_count,
      v_base_reward_points,
      v_base_mail_count,
      v_final_reward_count,
      v_final_high_count,
      v_final_standard_count,
      v_final_reward_points,
      v_final_ss_total,
      v_final_sss_total,
      v_original_final_mail_count,
      v_upgrade_count,
      v_upgrade_mail_count;
  end if;
end
$preflight$;

create temporary table soop_post_202512799_late_auth_base_awarded (
  user_id uuid primary key,
  soop_id text not null unique,
  points_before integer not null
) on commit drop;

with inserted as (
  insert into public.gacha_s2_soop_post_202512799_rewards (
    user_id,
    soop_id,
    points_before,
    points_granted,
    source_post_id
  )
  select
    target.user_id,
    target.soop_id,
    target.points_before,
    50000,
    202512799
  from soop_post_202512799_late_auth_targets target
  where not target.base_reward_exists
  on conflict do nothing
  returning user_id, soop_id, points_before
)
insert into soop_post_202512799_late_auth_base_awarded (
  user_id,
  soop_id,
  points_before
)
select user_id, soop_id, points_before
from inserted;

update public.gacha_s2_player_states state
set points = state.points + 50000,
    revision = state.revision + 1,
    updated_at = now()
from soop_post_202512799_late_auth_base_awarded awarded
where state.user_id = awarded.user_id;

update public.gacha_s2_soop_post_202512799_rewards reward
set points_after = state.points
from public.gacha_s2_player_states state
join soop_post_202512799_late_auth_base_awarded awarded
  on awarded.user_id = state.user_id
where reward.user_id = awarded.user_id
  and reward.source_post_id = 202512799
  and reward.soop_id = awarded.soop_id
  and reward.points_after is null;

do $base_mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id
    from soop_post_202512799_late_auth_base_awarded
    order by soop_id
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'soop-post-202512799:reward-50k',
      '[이벤트] 참여 보상 지급 완료',
      '이벤트 참여가 확인되어 50,000 포인트가 계정에 자동 반영되었습니다.',
      'REWARD',
      50000
    );

    if v_mail_id is null then
      raise exception 'late auth participation mailbox creation failed';
    end if;
  end loop;
end
$base_mail$;

create temporary table soop_post_202512799_late_auth_upgrade_awarded (
  user_id uuid primary key,
  soop_id text not null unique,
  points_before integer not null,
  sss_selector_before integer not null
) on commit drop;

with inserted as (
  insert into
    public.gacha_s2_soop_post_202512799_first_place_reward_upgrades (
      user_id,
      soop_id,
      source_post_id,
      points_before,
      sss_selector_before,
      points_granted,
      sss_selector_granted
    )
  select
    target.user_id,
    target.soop_id,
    202512799,
    state.points,
    coalesce((state.support_items->>'sssCardSelector')::integer, 0),
    50000,
    1
  from soop_post_202512799_late_auth_targets target
  join public.gacha_s2_player_states state
    on state.user_id = target.user_id
  join public.gacha_s2_soop_post_202512799_first_place_rewards final
    on final.user_id = target.user_id
   and final.tier = 'STANDARD'
  where not target.upgrade_exists
  on conflict do nothing
  returning user_id, soop_id, points_before, sss_selector_before
)
insert into soop_post_202512799_late_auth_upgrade_awarded (
  user_id,
  soop_id,
  points_before,
  sss_selector_before
)
select user_id, soop_id, points_before, sss_selector_before
from inserted;

update public.gacha_s2_player_states state
set points = state.points + 50000,
    support_items = jsonb_set(
      state.support_items,
      '{sssCardSelector}',
      to_jsonb(
        coalesce((state.support_items->>'sssCardSelector')::integer, 0) + 1
      ),
      true
    ),
    revision = state.revision + 1,
    updated_at = now()
from soop_post_202512799_late_auth_upgrade_awarded awarded
where state.user_id = awarded.user_id;

update
  public.gacha_s2_soop_post_202512799_first_place_reward_upgrades upgrade
set points_after = state.points,
    sss_selector_after =
      (state.support_items->>'sssCardSelector')::integer
from public.gacha_s2_player_states state
join soop_post_202512799_late_auth_upgrade_awarded awarded
  on awarded.user_id = state.user_id
where upgrade.user_id = awarded.user_id
  and upgrade.points_after is null;

update public.gacha_s2_soop_post_202512799_first_place_rewards final
set tier = 'HIGH',
    event_authenticated = true,
    points_granted = 100000,
    sss_selector_granted = 1,
    points_after = final.points_before + 100000,
    ss_selector_after = final.ss_selector_before + 1,
    sss_selector_after = final.sss_selector_before + 1
from soop_post_202512799_late_auth_upgrade_awarded awarded
where final.user_id = awarded.user_id
  and final.tier = 'STANDARD'
  and final.points_granted = 50000
  and final.ss_selector_granted = 1
  and final.sss_selector_granted = 0;

do $upgrade_mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id
    from soop_post_202512799_late_auth_upgrade_awarded
    order by soop_id
  loop
    v_mail_id := public.gacha_s2_deliver_mail(
      v_target.user_id,
      'soop-post-202512799:first-place-reward-upgrade',
      '[이벤트] 인증자 특별 보상 추가 지급 완료',
      '댓글 인증이 추가 확인되어 투표 1등 달성 특별 보상이 인증자 기준으로 상향되었습니다. 추가 50,000 포인트와 SSS 카드 선택권 1장이 지급되어, 기존 지급분을 포함한 특별 보상은 총 100,000 포인트, SS 카드 선택권 1장, SSS 카드 선택권 1장입니다.',
      'REWARD',
      50000
    );

    if v_mail_id is null then
      raise exception 'late auth upgrade mailbox creation failed';
    end if;
  end loop;
end
$upgrade_mail$;

do $verify$
declare
  v_base_reward_count integer;
  v_base_reward_points bigint;
  v_base_delta_error_count integer;
  v_base_mail_count integer;
  v_base_mail_payload_error_count integer;
  v_upgrade_count integer;
  v_upgrade_points bigint;
  v_upgrade_sss bigint;
  v_upgrade_delta_error_count integer;
  v_upgrade_mail_count integer;
  v_upgrade_mail_payload_error_count integer;
  v_final_high_count integer;
  v_final_points bigint;
  v_final_ss bigint;
  v_final_sss bigint;
  v_awarded_base_count integer;
  v_awarded_upgrade_count integer;
  v_awarded_state_error_count integer;
begin
  select
    count(*),
    coalesce(sum(reward.points_granted), 0),
    count(*) filter (
      where reward.points_after <> reward.points_before + 50000
    )
  into
    v_base_reward_count,
    v_base_reward_points,
    v_base_delta_error_count
  from public.gacha_s2_soop_post_202512799_rewards reward
  join soop_post_202512799_late_auth_source source
    on source.soop_id = reward.soop_id
  where reward.source_post_id = 202512799;

  select
    count(*),
    count(*) filter (
      where mail.title <> '[이벤트] 참여 보상 지급 완료'
        or mail.body <>
          '이벤트 참여가 확인되어 50,000 포인트가 계정에 자동 반영되었습니다.'
        or mail.category <> 'REWARD'
        or mail.points <> 50000
    )
  into v_base_mail_count, v_base_mail_payload_error_count
  from soop_post_202512799_late_auth_targets target
  join public.gacha_s2_mailbox mail
    on mail.user_id = target.user_id
   and mail.event_key = 'soop-post-202512799:reward-50k';

  select
    count(*),
    coalesce(sum(upgrade.points_granted), 0),
    coalesce(sum(upgrade.sss_selector_granted), 0),
    count(*) filter (
      where upgrade.points_after <> upgrade.points_before + 50000
        or upgrade.sss_selector_after <>
          upgrade.sss_selector_before + 1
    )
  into
    v_upgrade_count,
    v_upgrade_points,
    v_upgrade_sss,
    v_upgrade_delta_error_count
  from
    public.gacha_s2_soop_post_202512799_first_place_reward_upgrades upgrade
  join soop_post_202512799_late_auth_source source
    on source.soop_id = upgrade.soop_id;

  select
    count(*),
    count(*) filter (
      where mail.title <> '[이벤트] 인증자 특별 보상 추가 지급 완료'
        or mail.body <>
          '댓글 인증이 추가 확인되어 투표 1등 달성 특별 보상이 인증자 기준으로 상향되었습니다. 추가 50,000 포인트와 SSS 카드 선택권 1장이 지급되어, 기존 지급분을 포함한 특별 보상은 총 100,000 포인트, SS 카드 선택권 1장, SSS 카드 선택권 1장입니다.'
        or mail.category <> 'REWARD'
        or mail.points <> 50000
    )
  into v_upgrade_mail_count, v_upgrade_mail_payload_error_count
  from soop_post_202512799_late_auth_targets target
  join public.gacha_s2_mailbox mail
    on mail.user_id = target.user_id
   and mail.event_key =
     'soop-post-202512799:first-place-reward-upgrade';

  select
    count(*),
    coalesce(sum(final.points_granted), 0),
    coalesce(sum(final.ss_selector_granted), 0),
    coalesce(sum(final.sss_selector_granted), 0)
  into
    v_final_high_count,
    v_final_points,
    v_final_ss,
    v_final_sss
  from public.gacha_s2_soop_post_202512799_first_place_rewards final
  join soop_post_202512799_late_auth_targets target
    on target.user_id = final.user_id
  where final.tier = 'HIGH'
    and final.event_authenticated;

  select count(*)
  into v_awarded_base_count
  from soop_post_202512799_late_auth_base_awarded;

  select count(*)
  into v_awarded_upgrade_count
  from soop_post_202512799_late_auth_upgrade_awarded;

  select count(*)
  into v_awarded_state_error_count
  from soop_post_202512799_late_auth_upgrade_awarded awarded
  join public.gacha_s2_player_states state
    on state.user_id = awarded.user_id
  join
    public.gacha_s2_soop_post_202512799_first_place_reward_upgrades upgrade
    on upgrade.user_id = awarded.user_id
  where state.points <> upgrade.points_after
    or (state.support_items->>'sssCardSelector')::integer <>
      upgrade.sss_selector_after;

  if v_base_reward_count <> 5
    or v_base_reward_points <> 250000
    or v_base_delta_error_count <> 0
    or v_base_mail_count <> 5
    or v_base_mail_payload_error_count <> 0 then
    raise exception
      'late auth base verification failed: rewards %, points %, deltas %, mails %, payload errors %',
      v_base_reward_count,
      v_base_reward_points,
      v_base_delta_error_count,
      v_base_mail_count,
      v_base_mail_payload_error_count;
  end if;

  if v_upgrade_count <> 5
    or v_upgrade_points <> 250000
    or v_upgrade_sss <> 5
    or v_upgrade_delta_error_count <> 0
    or v_upgrade_mail_count <> 5
    or v_upgrade_mail_payload_error_count <> 0 then
    raise exception
      'late auth upgrade verification failed: upgrades %, points %, SSS %, deltas %, mails %, payload errors %',
      v_upgrade_count,
      v_upgrade_points,
      v_upgrade_sss,
      v_upgrade_delta_error_count,
      v_upgrade_mail_count,
      v_upgrade_mail_payload_error_count;
  end if;

  if v_final_high_count <> 5
    or v_final_points <> 500000
    or v_final_ss <> 5
    or v_final_sss <> 5 then
    raise exception
      'late auth effective final verification failed: high %, points %, SS %, SSS %',
      v_final_high_count,
      v_final_points,
      v_final_ss,
      v_final_sss;
  end if;

  if v_awarded_base_count not in (0, 5)
    or v_awarded_upgrade_count not in (0, 5)
    or v_awarded_base_count <> v_awarded_upgrade_count
    or v_awarded_state_error_count <> 0 then
    raise exception
      'late auth awarded-state verification failed: base %, upgrades %, state errors %',
      v_awarded_base_count,
      v_awarded_upgrade_count,
      v_awarded_state_error_count;
  end if;
end
$verify$;

commit;
