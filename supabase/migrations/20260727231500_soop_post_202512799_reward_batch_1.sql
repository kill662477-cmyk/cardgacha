-- Manual recovery for the missed 2026-07-27 23:00 KST SOOP comment-event run.
-- Only commenters with an image and a linked Season 2 player state are eligible.

begin;

lock table public.gacha_s2_player_states in share row exclusive mode;

create table if not exists public.gacha_s2_soop_post_202512799_rewards (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  soop_id text not null unique,
  points_before integer not null,
  points_granted integer not null default 50000 check (points_granted = 50000),
  points_after integer,
  source_post_id bigint not null default 202512799 check (source_post_id = 202512799),
  granted_at timestamptz not null default now()
);

with target(soop_id) as (
  values
    ('javasoccer'),
    ('tjdrb0627'),
    ('brainzerg777'),
    ('bliter82'),
    ('rlawltn125'),
    ('oonon4'),
    ('kdg2973'),
    ('wkdlfhdlzksh'),
    ('01198824896'),
    ('jhha0511'),
    ('rlslxl12'),
    ('sookin1408'),
    ('ekrcu99'),
    ('stereohearts'),
    ('rlaaudwn5'),
    ('frank022'),
    ('fowjd0'),
    ('mang2202'),
    ('power2103'),
    ('clubmp'),
    ('gnldud214'),
    ('ngundamhj'),
    ('shm7969'),
    ('moonsjoon'),
    ('onlytomato'),
    ('honghint'),
    ('wkdskfk318'),
    ('sheng0124'),
    ('hj99087'),
    ('wonsang1580'),
    ('ktntntn14'),
    ('sayonara164'),
    ('know888'),
    ('hsw926'),
    ('rickyoh0118'),
    ('nrtusak47'),
    ('kyy2342'),
    ('onlyforme'),
    ('rmacl1'),
    ('dudwns774'),
    ('ngudcks774'),
    ('cmk929'),
    ('joyfulyama'),
    ('kbs128'),
    ('akak9909'),
    ('252nds'),
    ('qkqhdhkdwk'),
    ('degurida'),
    ('tmdgus5218'),
    ('lyg1492'),
    ('pch2771'),
    ('dodkdkgo'),
    ('koo1234567'),
    ('ncc168'),
    ('nalscjf2tp'),
    ('ruddhks9749'),
    ('disthorsound'),
    ('jee2305'),
    ('dhastar'),
    ('sesstalker'),
    ('didtldls'),
    ('yayatoto'),
    ('dfhdfhfdh'),
    ('senzze'),
    ('destiny155'),
    ('usevery37'),
    ('alfy94'),
    ('koodaeh'),
    ('alskfl42'),
    ('deckwon4'),
    ('calmaeng'),
    ('kuahn6933'),
    ('vlvlak123123'),
    ('lonarave'),
    ('glacis'),
    ('seivies'),
    ('krotemple'),
    ('sst12'),
    ('hgtk2k'),
    ('pppsssjjj123'),
    ('gudtjs0628'),
    ('nqaddict89'),
    ('ehsrkekd'),
    ('rhdrkr147'),
    ('llliiiiillii'),
    ('redshark95'),
    ('guest123')
)
insert into public.gacha_s2_soop_post_202512799_rewards (
  user_id,
  soop_id,
  points_before
)
select
  account.id,
  lower(trim(account.soop_id)),
  state.points
from target
join public.gacha_s2_accounts account
  on lower(trim(account.soop_id)) = target.soop_id
join public.gacha_s2_player_states state
  on state.user_id = account.id
on conflict do nothing;

update public.gacha_s2_player_states state
set points = state.points + reward.points_granted,
    revision = state.revision + 1,
    updated_at = now()
from public.gacha_s2_soop_post_202512799_rewards reward
where state.user_id = reward.user_id
  and reward.points_after is null;

update public.gacha_s2_soop_post_202512799_rewards reward
set points_after = state.points
from public.gacha_s2_player_states state
where state.user_id = reward.user_id
  and reward.points_after is null;

do $mail$
declare
  v_reward record;
begin
  for v_reward in
    select user_id
    from public.gacha_s2_soop_post_202512799_rewards
    where points_after is not null
  loop
    perform public.gacha_s2_deliver_mail(
      v_reward.user_id,
      'soop-post-202512799:reward-50k',
      '[이벤트] 참여 보상 지급 완료',
      '이벤트 참여가 확인되어 50,000 포인트가 계정에 자동 반영되었습니다.',
      'REWARD',
      50000
    );
  end loop;
end
$mail$;

do $verify$
declare
  v_reward_count integer;
  v_reward_total bigint;
  v_mail_count integer;
begin
  select count(*), coalesce(sum(points_granted), 0)
  into v_reward_count, v_reward_total
  from public.gacha_s2_soop_post_202512799_rewards;

  select count(*)
  into v_mail_count
  from public.gacha_s2_mailbox
  where event_key = 'soop-post-202512799:reward-50k';

  if v_reward_count < 84 or v_reward_count > 87 then
    raise exception 'SOOP event reward target count mismatch: expected 84..87, actual %',
      v_reward_count;
  end if;

  if v_reward_total <> v_reward_count::bigint * 50000 then
    raise exception 'SOOP event reward total mismatch';
  end if;

  if v_mail_count <> v_reward_count then
    raise exception 'SOOP event reward mailbox count mismatch: rewards %, mails %',
      v_reward_count, v_mail_count;
  end if;

  if exists (
    select 1
    from public.gacha_s2_soop_post_202512799_rewards
    where points_after is null
       or points_after <> points_before + points_granted
  ) then
    raise exception 'SOOP event reward amount validation failed';
  end if;
end
$verify$;

revoke all on table public.gacha_s2_soop_post_202512799_rewards
  from public, anon, authenticated;
grant select on table public.gacha_s2_soop_post_202512799_rewards
  to service_role;

commit;
