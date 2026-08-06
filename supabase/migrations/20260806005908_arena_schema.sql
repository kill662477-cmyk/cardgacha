-- 투기장(비동기 PvP) 스키마.
-- 공격자가 판을 열면 서버가 비슷한 레이팅의 상대를 골라 대기 매치를 만들고,
-- Edge 가 양쪽 편성으로 전투를 재현한 뒤 결과를 확정한다. 방어자는 접속할 필요가 없다.
create table if not exists public.gacha_s2_arena_players (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  rating integer not null default 1000 check (rating >= 0),
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  defend_wins integer not null default 0 check (defend_wins >= 0),
  defend_losses integer not null default 0 check (defend_losses >= 0),
  -- 주간 정산 대상 판별용. 그 주에 공격을 한 번이라도 했는지 본다.
  week_key text,
  week_attacks integer not null default 0 check (week_attacks >= 0),
  peak_rating integer not null default 1000,
  last_match_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists gacha_s2_arena_players_rating_idx
  on public.gacha_s2_arena_players (rating desc, user_id);

create table if not exists public.gacha_s2_arena_matches (
  match_id uuid primary key default gen_random_uuid(),
  attacker_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  defender_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'resolved')),
  command_id text not null,
  attacker_rating_before integer not null,
  defender_rating_before integer not null,
  attacker_rating_after integer,
  defender_rating_after integer,
  attacker_won boolean,
  reason text check (reason is null or reason in ('knockout', 'speed', 'survival', 'damage')),
  attacker_formation jsonb not null,
  defender_formation jsonb not null,
  week_key text not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  -- 대기 상태에서는 결과가 비어 있고, 확정되면 전부 채워져야 한다.
  constraint gacha_s2_arena_matches_result_check check (
    (status = 'pending' and attacker_won is null and resolved_at is null)
    or (status = 'resolved' and attacker_won is not null and resolved_at is not null
        and attacker_rating_after is not null and defender_rating_after is not null)
  ),
  constraint gacha_s2_arena_matches_self_check check (attacker_id <> defender_id),
  unique (attacker_id, command_id)
);

create index if not exists gacha_s2_arena_matches_attacker_idx
  on public.gacha_s2_arena_matches (attacker_id, created_at desc);
create index if not exists gacha_s2_arena_matches_defender_idx
  on public.gacha_s2_arena_matches (defender_id, created_at desc);
create index if not exists gacha_s2_arena_matches_week_idx
  on public.gacha_s2_arena_matches (week_key, created_at desc);

create table if not exists public.gacha_s2_arena_weekly_rewards (
  week_key text not null,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  rank integer not null check (rank >= 1),
  rating integer not null,
  attacks integer not null,
  points integer not null check (points >= 0),
  rating_after_reset integer not null,
  granted_at timestamptz not null default now(),
  primary key (week_key, user_id)
);

alter table public.gacha_s2_arena_players enable row level security;
alter table public.gacha_s2_arena_matches enable row level security;
alter table public.gacha_s2_arena_weekly_rewards enable row level security;
revoke all on table public.gacha_s2_arena_players from public, anon, authenticated;
revoke all on table public.gacha_s2_arena_matches from public, anon, authenticated;
revoke all on table public.gacha_s2_arena_weekly_rewards from public, anon, authenticated;

-- 주 구분자. 월요일 00:00 KST 시작.
create or replace function public.gacha_s2_arena_week_key(p_now timestamp with time zone default now())
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select to_char(date_trunc('week', (p_now at time zone 'Asia/Seoul')), 'IYYY-"W"IW');
$$;

-- 이번 시간대에 쓴 공격 횟수. 매 정각 초기화되고 미사용분은 이월되지 않는다.
create or replace function public.gacha_s2_arena_attempts_used(p_user_id uuid, p_now timestamp with time zone default now())
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select count(*)::integer
  from public.gacha_s2_arena_matches
  where attacker_id = p_user_id
    and created_at >= date_trunc('hour', p_now)
    and created_at < date_trunc('hour', p_now) + interval '1 hour';
$$;

create or replace function public.gacha_s2_arena_ensure_player(p_user_id uuid)
returns public.gacha_s2_arena_players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.gacha_s2_arena_players%rowtype;
begin
  insert into public.gacha_s2_arena_players (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;
  select * into v_row from public.gacha_s2_arena_players where user_id = p_user_id;
  return v_row;
end;
$$;

-- 현재 등수. 동점이면 user_id 로 갈라 항상 같은 순서가 나오게 한다.
create or replace function public.gacha_s2_arena_rank_of(p_user_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_rating integer;
  v_rank integer;
begin
  select rating into v_rating from public.gacha_s2_arena_players where user_id = p_user_id;
  if v_rating is null then return null; end if;
  select count(*)::integer + 1 into v_rank
  from public.gacha_s2_arena_players other
  where other.rating > v_rating
     or (other.rating = v_rating and other.user_id > p_user_id);
  return v_rank;
end;
$$;
