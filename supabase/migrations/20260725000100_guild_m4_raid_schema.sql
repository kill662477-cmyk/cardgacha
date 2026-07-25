-- 길드 M4: 길드 레이드 스키마와 회차 생성 (PDB-16 3.3)
--
-- 월드보스와 같은 합산딜 구조를 쓰되 두 가지가 다르다.
--   1) 서버 자동딜이 없다(월드보스도 2026-07-25 폐지). 순수 참여자 합산딜로만 처치한다.
--   2) 처치 성공 시 참여 여부와 무관하게 길드원 전원이 보상을 받는다.
--      대신 난이도를 다수 참여 전제로 잡아, 참여가 적으면 아무도 못 받는다.
--
-- HP 는 "참여자 수"가 아니라 "활동 길드원 수" 기준으로 시작 시점에 고정한다.
-- 참여자 비례로 두면 몇 명이 오든 난이도가 같아져 다수 참여 유인이 사라진다.

create table if not exists public.gacha_s2_guild_raids (
  raid_id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.gacha_s2_guilds(guild_id) on delete cascade,
  starts_at timestamptz not null,
  raid_ends_at timestamptz not null,
  ends_at timestamptz not null,
  -- HP 산정 근거. 진행 중 가입·탈퇴로 난이도가 흔들리지 않도록 스냅샷으로 남긴다.
  active_member_count integer not null check (active_member_count >= 0),
  max_hp bigint not null check (max_hp > 0),
  current_hp bigint not null check (current_hp >= 0 and current_hp <= max_hp),
  player_damage bigint not null default 0 check (player_damage >= 0),
  defeated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (guild_id, starts_at),
  check (raid_ends_at > starts_at and ends_at > raid_ends_at)
);

-- 보상 대상 명단. 회차 시작 시점의 소속 길드원 전원에 대해 미리 만든다.
-- 이 스냅샷이 있어야 처치 후 가입해 보상만 받는 어뷰징을 막고,
-- 종료 후 "누가 참여하지 않았는지"를 보여 줄 수 있다(PDB-16 3.3 참여자 현황).
create table if not exists public.gacha_s2_guild_raid_players (
  raid_id uuid not null references public.gacha_s2_guild_raids(raid_id) on delete cascade,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  attempts integer not null default 0 check (attempts between 0 and 3),
  total_damage bigint not null default 0 check (total_damage >= 0),
  best_damage bigint not null default 0 check (best_damage >= 0),
  claimed_at timestamptz,
  reward_points integer not null default 0 check (reward_points between 0 and 100000),
  primary key (raid_id, user_id)
);
create index if not exists gacha_s2_guild_raid_players_damage_idx
  on public.gacha_s2_guild_raid_players (raid_id, total_damage desc);

-- 현재 유효한 레이드 슬롯의 시작 시각. 수·토 21:00 KST, 전투 30분 + 결과 30분.
-- 유효 구간(1시간) 밖이면 null 을 돌려준다.
create or replace function public.gacha_s2_guild_raid_current_slot(p_now timestamptz default now())
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_kst timestamp;
  v_start timestamp;
  i integer;
begin
  v_kst := p_now at time zone 'Asia/Seoul';
  -- 자정 직후에는 전날 21시 회차의 결과 창이 아직 열려 있을 수 있어 하루 전까지 본다.
  for i in 0..1 loop
    v_start := date_trunc('day', v_kst) - (i || ' days')::interval + interval '21 hours';
    if extract(isodow from v_start) in (3, 6)
      and v_kst >= v_start
      and v_kst < v_start + interval '1 hour' then
      return v_start at time zone 'Asia/Seoul';
    end if;
  end loop;
  return null;
end;
$$;

-- 회차를 보장하고 현재 상태를 돌려준다. 슬롯이 아니면 null.
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

alter table public.gacha_s2_guild_raids enable row level security;
alter table public.gacha_s2_guild_raid_players enable row level security;
revoke all on table public.gacha_s2_guild_raids from public, anon, authenticated;
revoke all on table public.gacha_s2_guild_raid_players from public, anon, authenticated;
revoke all on function public.gacha_s2_guild_raid_current_slot(timestamptz) from public, anon, authenticated;
revoke all on function public.gacha_s2_ensure_guild_raid(uuid, timestamptz) from public, anon, authenticated;
