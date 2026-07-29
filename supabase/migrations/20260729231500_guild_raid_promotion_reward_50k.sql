-- 길드 레이드 홍보: 현재 시즌2 전 계정 50,000P 자동 지급 + 개인 우편 안내.
-- 레이드는 매주 수요일·토요일 21:00 KST에 열린다.

begin;

lock table public.gacha_s2_player_states in share row exclusive mode;
lock table public.gacha_s2_mailbox in share row exclusive mode;

create table if not exists public.gacha_s2_guild_raid_promotion_reward_20260729 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  points_before integer not null,
  points_granted integer not null default 50000 check (points_granted = 50000),
  points_after integer,
  granted_at timestamptz not null default now()
);

-- 최초 실행 때의 계정만 대상에 고정한다. 재실행 시 신규 계정이 뒤늦게 섞이지 않는다.
insert into public.gacha_s2_guild_raid_promotion_reward_20260729 (
  user_id,
  points_before
)
select state.user_id, state.points
from public.gacha_s2_player_states state
where not exists (
  select 1
  from public.gacha_s2_guild_raid_promotion_reward_20260729
)
on conflict (user_id) do nothing;

-- 우편의 points는 표시용이다. 실제 포인트는 원장에서 한 번만 직접 반영한다.
update public.gacha_s2_player_states state
set points = state.points + reward.points_granted,
    revision = state.revision + 1,
    updated_at = now()
from public.gacha_s2_guild_raid_promotion_reward_20260729 reward
where state.user_id = reward.user_id
  and reward.points_after is null;

update public.gacha_s2_guild_raid_promotion_reward_20260729 reward
set points_after = state.points
from public.gacha_s2_player_states state
where state.user_id = reward.user_id
  and reward.points_after is null;

insert into public.gacha_s2_mailbox (
  user_id,
  event_key,
  category,
  title,
  body,
  points
)
select
  reward.user_id,
  'guild-raid-promotion-20260729',
  'EVENT',
  '길드 레이드 오픈 안내 · 50,000P 지급',
  E'길드 레이드 홍보 기념으로 50,000P가 계정에 자동 지급되었습니다.\n\n'
    || E'길드 레이드는 매주 수요일·토요일 21:00 KST에 열립니다.\n'
    || E'길드 화면에서 「길드 레이드 입장」 버튼을 눌러 참여할 수 있습니다.\n\n'
    || E'길드원과 함께 보스를 처치하고 협동 보상에 도전해 주세요!',
  50000
from public.gacha_s2_guild_raid_promotion_reward_20260729 reward
on conflict (user_id, event_key) do nothing;

do $verify$
declare
  v_reward_count integer;
  v_reward_total bigint;
  v_mail_count integer;
begin
  select count(*), coalesce(sum(points_granted), 0)
  into v_reward_count, v_reward_total
  from public.gacha_s2_guild_raid_promotion_reward_20260729;

  if v_reward_count = 0 then
    raise exception 'guild raid promotion reward has no target accounts';
  end if;

  if v_reward_total <> v_reward_count::bigint * 50000 then
    raise exception 'guild raid promotion reward total mismatch: count %, total %',
      v_reward_count, v_reward_total;
  end if;

  if exists (
    select 1
    from public.gacha_s2_guild_raid_promotion_reward_20260729
    where points_after is null
       or points_after <> points_before + points_granted
  ) then
    raise exception 'guild raid promotion reward amount validation failed';
  end if;

  select count(*) into v_mail_count
  from public.gacha_s2_mailbox mail
  join public.gacha_s2_guild_raid_promotion_reward_20260729 reward
    on reward.user_id = mail.user_id
  where mail.event_key = 'guild-raid-promotion-20260729'
    and mail.category = 'EVENT'
    and mail.points = 50000;

  if v_mail_count <> v_reward_count then
    raise exception 'guild raid promotion mailbox mismatch: rewards %, mails %',
      v_reward_count, v_mail_count;
  end if;
end
$verify$;

revoke all on table public.gacha_s2_guild_raid_promotion_reward_20260729
  from public, anon, authenticated;

commit;
