-- SOOP post 202512799 event reward, batch 7.
-- Live comments were re-read on 2026-07-30 KST. Only image commenters
-- with exactly one linked Season 2 account and player state are included.

begin;

lock table public.gacha_s2_accounts in share mode;
lock table public.gacha_s2_player_states in share row exclusive mode;
lock table public.gacha_s2_soop_post_202512799_rewards in share row exclusive mode;
lock table public.gacha_s2_mailbox in share row exclusive mode;

create temporary table soop_post_202512799_batch_7_source (
  soop_id text primary key
) on commit drop;

insert into soop_post_202512799_batch_7_source (soop_id)
values
  ('jjmk0222'),
  ('psh730');

do $preflight$
declare
  v_target_count integer;
  v_account_match_count integer;
  v_account_count integer;
  v_player_state_count integer;
  v_existing_reward_count integer;
  v_existing_mail_count integer;
begin
  with account_matches as (
    select source.soop_id, account.id
    from soop_post_202512799_batch_7_source source
    join public.gacha_s2_accounts account
      on lower(trim(account.soop_id)) = source.soop_id
  )
  select
    (select count(*) from soop_post_202512799_batch_7_source),
    (select count(*) from account_matches),
    (select count(distinct id) from account_matches),
    (
      select count(*)
      from account_matches matched
      join public.gacha_s2_player_states state
        on state.user_id = matched.id
    ),
    (
      select count(*)
      from account_matches matched
      join public.gacha_s2_soop_post_202512799_rewards reward
        on reward.user_id = matched.id
        or (
          reward.source_post_id = 202512799
          and reward.soop_id = matched.soop_id
        )
    ),
    (
      select count(*)
      from account_matches matched
      join public.gacha_s2_mailbox mail
        on mail.user_id = matched.id
       and mail.event_key = 'soop-post-202512799:reward-50k'
    )
  into
    v_target_count,
    v_account_match_count,
    v_account_count,
    v_player_state_count,
    v_existing_reward_count,
    v_existing_mail_count;

  if v_target_count <> 2 then
    raise exception 'SOOP event batch 7 target mismatch: expected 2, actual %', v_target_count;
  end if;

  if v_account_match_count <> 2 or v_account_count <> 2 then
    raise exception
      'SOOP event batch 7 account mismatch: matches %, accounts %',
      v_account_match_count,
      v_account_count;
  end if;

  if v_player_state_count <> 2 then
    raise exception
      'SOOP event batch 7 player-state mismatch: expected 2, actual %',
      v_player_state_count;
  end if;

  if v_existing_reward_count <> v_existing_mail_count
     or v_existing_reward_count not in (0, 2) then
    raise exception
      'SOOP event batch 7 partial prior state: rewards %, mails %',
      v_existing_reward_count,
      v_existing_mail_count;
  end if;
end
$preflight$;

create temporary table soop_post_202512799_batch_7 (
  user_id uuid primary key,
  soop_id text not null unique,
  game_nickname text not null,
  points_before integer not null
) on commit drop;

insert into soop_post_202512799_batch_7 (
  user_id,
  soop_id,
  game_nickname,
  points_before
)
select
  account.id,
  lower(trim(account.soop_id)),
  account.nickname,
  state.points
from soop_post_202512799_batch_7_source source
join public.gacha_s2_accounts account
  on lower(trim(account.soop_id)) = source.soop_id
join public.gacha_s2_player_states state
  on state.user_id = account.id;

create temporary table soop_post_202512799_batch_7_awarded (
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
  from soop_post_202512799_batch_7 target
  on conflict do nothing
  returning user_id, soop_id, points_before
)
insert into soop_post_202512799_batch_7_awarded (
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
from soop_post_202512799_batch_7_awarded awarded
where state.user_id = awarded.user_id;

update public.gacha_s2_soop_post_202512799_rewards reward
set points_after = state.points
from public.gacha_s2_player_states state
join soop_post_202512799_batch_7_awarded awarded
  on awarded.user_id = state.user_id
where reward.user_id = awarded.user_id
  and reward.source_post_id = 202512799
  and reward.soop_id = awarded.soop_id
  and reward.points_after is null;

do $mail$
declare
  v_target record;
  v_mail_id uuid;
begin
  for v_target in
    select user_id
    from soop_post_202512799_batch_7_awarded
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
      raise exception 'SOOP event batch 7 mailbox creation failed';
    end if;
  end loop;
end
$mail$;

do $verify$
declare
  v_reward_count integer;
  v_reward_total bigint;
  v_mail_count integer;
begin
  select count(*), coalesce(sum(reward.points_granted), 0)
  into v_reward_count, v_reward_total
  from public.gacha_s2_soop_post_202512799_rewards reward
  join soop_post_202512799_batch_7_source source
    on source.soop_id = reward.soop_id
  where reward.source_post_id = 202512799
    and reward.points_after = reward.points_before + 50000;

  select count(*)
  into v_mail_count
  from public.gacha_s2_mailbox mail
  join public.gacha_s2_accounts account
    on account.id = mail.user_id
  join soop_post_202512799_batch_7_source source
    on source.soop_id = lower(trim(account.soop_id))
  where mail.event_key = 'soop-post-202512799:reward-50k'
    and mail.category = 'REWARD'
    and mail.points = 50000;

  if v_reward_count <> 2 or v_reward_total <> 100000 then
    raise exception
      'SOOP event batch 7 reward verification failed: count %, total %',
      v_reward_count,
      v_reward_total;
  end if;

  if v_mail_count <> 2 then
    raise exception
      'SOOP event batch 7 mailbox verification failed: expected 2, actual %',
      v_mail_count;
  end if;
end
$verify$;

commit;
