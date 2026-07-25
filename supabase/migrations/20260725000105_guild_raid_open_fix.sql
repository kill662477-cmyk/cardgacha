-- 길드레이드 회차가 영영 생성되지 않던 버그 수정.
--
-- 증상: 2026-07-25(토) 21:00 슬롯에 보스가 뜨지 않았다. gacha_s2_guild_raids 가 빈 테이블이었다.
--
-- 원인: 회차 행을 만드는 gacha_s2_ensure_guild_raid 를 호출하는 곳이
-- gacha_s2_attack_guild_raid 하나뿐이었다. 그런데 공격 버튼은 조회 함수
-- gacha_s2_get_guild_raid_status 가 회차를 돌려줘야 열린다.
--   행 없음 -> 조회가 active:false 반환 -> 공격 불가 -> 행이 영영 안 생김
-- 조회 함수가 stable 로 선언돼 있어 INSERT 하는 ensure 를 부를 수 없던 것이 근본 원인이다.
-- (월드보스는 gacha_s2_ensure_world_boss_schedule 이 회차를 선생성해 이 문제가 없었다.)
--
-- 수정 두 갈래:
--   1) 조회 함수를 volatile 로 바꾸고, 슬롯 시간대면 ensure 를 먼저 호출한다.
--      -> 누구든 길드 화면을 열면 그 자리에서 회차가 생긴다(자가 치유).
--   2) 크론이 5분마다 전 길드 회차를 선생성한다.
--      -> 아무도 화면을 안 열어도 회차는 존재한다. 아무도 안 열면 1)만으로는 안 생긴다.
-- 슬롯 시간대가 아니면 ensure 가 즉시 null 을 돌려주므로 평상시 비용은 사실상 없다.
--
-- 동시성: 여러 명이 21:00 에 동시에 열어도 ensure 안의
-- on conflict (guild_id, starts_at) do nothing + 재조회 경로가 이미 처리한다.

-- 회차 생성을 전투 시간(슬롯 +30분) 안으로 제한한다.
-- 결과 창(+30분~+60분)에 회차가 새로 생기면 아무도 공격할 수 없는 빈 회차가 만들어져
-- "참여 기록 없는 실패 레이드"만 남는다. 이미 존재하는 회차 조회는 결과 창에서도 정상 동작해야
-- 보상 수령이 되므로, 막는 것은 INSERT 뿐이다.
create or replace function public.gacha_s2_ensure_guild_raid(
  p_guild_id uuid,
  p_now timestamptz default now()
) returns public.gacha_s2_guild_raids
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_slot timestamptz;
  v_raid public.gacha_s2_guild_raids%rowtype;
  v_active integer;
  v_hp bigint;
begin
  v_slot := public.gacha_s2_guild_raid_current_slot(p_now);
  if v_slot is null then return null; end if;

  select * into v_raid from public.gacha_s2_guild_raids
  where guild_id = p_guild_id and starts_at = v_slot;
  if found then return v_raid; end if;

  if p_now >= v_slot + interval '30 minutes' then
    return null;
  end if;

  -- 활동 길드원: 최근 7일 안에 공헌 기록이 있는 인원.
  -- 가입만 하고 접속하지 않는 유령 회원까지 HP 에 넣으면 실제 활동 인원이 전원
  -- 참여해도 처치가 불가능해진다.
  select count(*) into v_active
  from public.gacha_s2_guild_members
  where guild_id = p_guild_id
    and last_contributed_at is not null
    and last_contributed_at >= p_now - interval '7 days';

  -- 활동 기록이 아직 없는 신생 길드도 최소 1인 기준은 잡아 준다(HP 0 방지).
  v_hp := greatest(v_active, 1)::bigint * 21000000;

  insert into public.gacha_s2_guild_raids (
    guild_id, starts_at, raid_ends_at, ends_at, active_member_count, max_hp, current_hp
  ) values (
    p_guild_id, v_slot, v_slot + interval '30 minutes', v_slot + interval '1 hour',
    v_active, v_hp, v_hp
  )
  on conflict (guild_id, starts_at) do nothing
  returning * into v_raid;

  if v_raid.raid_id is null then
    select * into v_raid from public.gacha_s2_guild_raids
    where guild_id = p_guild_id and starts_at = v_slot;
    return v_raid;
  end if;

  -- 시작 시점 소속 전원을 보상 대상으로 등록한다(미참여자 포함).
  insert into public.gacha_s2_guild_raid_players (raid_id, user_id)
  select v_raid.raid_id, m.user_id
  from public.gacha_s2_guild_members m
  where m.guild_id = p_guild_id
  on conflict do nothing;

  return v_raid;
end;
$$;

revoke all on function public.gacha_s2_ensure_guild_raid(uuid, timestamptz) from public, anon, authenticated;

-- 슬롯 시간대의 모든 활성 길드 회차를 선생성한다.
create or replace function public.gacha_s2_open_guild_raids(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_slot timestamptz;
  v_guild record;
  v_opened integer := 0;
begin
  v_slot := public.gacha_s2_guild_raid_current_slot(p_now);
  if v_slot is null then return 0; end if;

  for v_guild in
    select guild_id from public.gacha_s2_guilds where disbanded_at is null
  loop
    perform public.gacha_s2_ensure_guild_raid(v_guild.guild_id, p_now);
    v_opened := v_opened + 1;
  end loop;

  return v_opened;
end;
$$;

revoke all on function public.gacha_s2_open_guild_raids(timestamptz) from public, anon, authenticated;

-- 조회 함수: stable -> volatile, 그리고 슬롯이면 회차를 보장한다.
create or replace function public.gacha_s2_get_guild_raid_status(p_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_guild_id uuid;
  v_raid public.gacha_s2_guild_raids%rowtype;
  v_now timestamptz := now();
  v_slot timestamptz;
begin
  select gm.guild_id into v_guild_id from public.gacha_s2_guild_membership(p_user_id) gm;
  if v_guild_id is null then return jsonb_build_object('active', false, 'raid', null); end if;

  v_slot := public.gacha_s2_guild_raid_current_slot(v_now);
  -- 슬롯 시간대인데 아직 회차가 없으면 여기서 만든다. 이게 빠져 있어서 보스가 안 떴다.
  if v_slot is not null then
    perform public.gacha_s2_ensure_guild_raid(v_guild_id, v_now);
  end if;

  select * into v_raid from public.gacha_s2_guild_raids
  where guild_id = v_guild_id and (v_slot is null or starts_at = v_slot)
  order by starts_at desc limit 1;

  if v_raid.raid_id is null then
    return jsonb_build_object('active', false, 'raid', null, 'nextSlot', null);
  end if;

  return jsonb_build_object(
    'active', v_now >= v_raid.starts_at and v_now < v_raid.raid_ends_at and v_raid.current_hp > 0,
    'resultsOpen', v_now >= v_raid.raid_ends_at and v_now < v_raid.ends_at,
    'raid', jsonb_build_object(
      'raidId', v_raid.raid_id,
      'startsAt', floor(extract(epoch from v_raid.starts_at) * 1000)::bigint,
      'raidEndsAt', floor(extract(epoch from v_raid.raid_ends_at) * 1000)::bigint,
      'endsAt', floor(extract(epoch from v_raid.ends_at) * 1000)::bigint,
      'maxHp', v_raid.max_hp,
      'currentHp', v_raid.current_hp,
      'playerDamage', v_raid.player_damage,
      'activeMemberCount', v_raid.active_member_count,
      'defeated', v_raid.current_hp = 0
    ),
    'me', (
      select jsonb_build_object('attempts', p.attempts, 'totalDamage', p.total_damage,
        'claimed', p.claimed_at is not null, 'rewardPoints', p.reward_points)
      from public.gacha_s2_guild_raid_players p
      where p.raid_id = v_raid.raid_id and p.user_id = p_user_id
    ),
    -- 미참여자도 포함해야 누가 빠졌는지 알 수 있다.
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', p.user_id, 'nickname', a.nickname,
        'attempts', p.attempts, 'totalDamage', p.total_damage,
        'claimed', p.claimed_at is not null
      ) order by p.total_damage desc, a.nickname)
      from public.gacha_s2_guild_raid_players p
      join public.gacha_s2_accounts a on a.id = p.user_id
      where p.raid_id = v_raid.raid_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.gacha_s2_get_guild_raid_status(uuid) from public, anon, authenticated;
grant execute on function public.gacha_s2_get_guild_raid_status(uuid) to service_role;

-- 5분마다 회차를 선생성한다. 슬롯 시간대가 아니면 즉시 0 을 돌려주는 no-op 이라
-- 상시 실행해도 부담이 없고, 크론 타임존 가정을 하지 않아도 된다.
select cron.unschedule('gacha-s2-guild-raid-open')
where exists (select 1 from cron.job where jobname = 'gacha-s2-guild-raid-open');

select cron.schedule(
  'gacha-s2-guild-raid-open',
  '*/5 * * * *',
  $cron$select public.gacha_s2_open_guild_raids()$cron$
);
