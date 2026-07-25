-- 길드 M1 스키마 (PDB-16)
--
-- 길드 뼈대: 생성·해산·가입 신청·승인(수동/자동)·탈퇴·추방·재가입 페널티.
-- 공헌도(GP)·공동목표·레이드는 M2 이후 단계에서 추가한다.
--
-- 접근 통제는 기존 테이블과 동일하다. RLS를 켜고 public/anon/authenticated 권한을
-- 모두 회수해, service_role로 실행되는 SECURITY DEFINER RPC만 접근하게 한다.

-- 엠블럼 목록을 테이블로 둔다. 커스텀 엠블럼을 추가할 때 스키마 변경 없이
-- 파일 배치 + 행 삽입만으로 확장할 수 있다(PDB-16 7.2).
create table if not exists public.gacha_s2_guild_emblems (
  emblem_key text primary key check (emblem_key ~ '^[a-z0-9_-]{2,32}$'),
  label text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.gacha_s2_guild_emblems (emblem_key, label, sort_order) values
  ('shield',  '방패',      10),
  ('bolt',    '번개',      20),
  ('star',    '별',        30),
  ('crown',   '왕관',      40),
  ('flame',   '불꽃',      50),
  ('blade',   '검',        60),
  ('hexcore', '육각 코어', 70),
  ('signal',  '전파 신호', 80)
on conflict (emblem_key) do nothing;

create table if not exists public.gacha_s2_guilds (
  guild_id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 20),
  tag text check (tag is null or length(trim(tag)) between 1 and 6),
  notice text not null default '' check (length(notice) <= 500),
  emblem text not null default 'shield' references public.gacha_s2_guild_emblems(emblem_key),
  join_mode text not null default 'approval' check (join_mode in ('approval', 'auto')),
  level integer not null default 1 check (level between 1 and 30),
  total_gp bigint not null default 0 check (total_gp >= 0),
  member_limit integer not null default 30 check (member_limit between 1 and 50),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  disbanded_at timestamptz
);

-- 해산한 길드는 기록으로 남기되 이름과 소유권은 다시 쓸 수 있어야 하므로
-- 활성 길드에만 유일성을 건다.
create unique index if not exists gacha_s2_guilds_owner_active_idx
  on public.gacha_s2_guilds (owner_user_id) where disbanded_at is null;
create unique index if not exists gacha_s2_guilds_name_active_idx
  on public.gacha_s2_guilds (lower(name)) where disbanded_at is null;

create table if not exists public.gacha_s2_guild_members (
  guild_id uuid not null references public.gacha_s2_guilds(guild_id) on delete cascade,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'officer', 'member')),
  joined_at timestamptz not null default now(),
  weekly_gp integer not null default 0 check (weekly_gp >= 0),
  total_gp bigint not null default 0 check (total_gp >= 0),
  last_contributed_at timestamptz,
  primary key (guild_id, user_id)
);

-- 1인 1길드. 소속은 계정당 하나만 존재한다.
create unique index if not exists gacha_s2_guild_members_user_idx
  on public.gacha_s2_guild_members (user_id);
create index if not exists gacha_s2_guild_members_guild_weekly_idx
  on public.gacha_s2_guild_members (guild_id, weekly_gp);

create table if not exists public.gacha_s2_guild_join_requests (
  guild_id uuid not null references public.gacha_s2_guilds(guild_id) on delete cascade,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.gacha_s2_accounts(id),
  primary key (guild_id, user_id),
  check ((status = 'pending' and resolved_at is null) or (status <> 'pending' and resolved_at is not null))
);

-- 신청 목록 조회(길드별 대기 목록, 유저별 동시 신청 수 제한)용.
create index if not exists gacha_s2_guild_join_requests_guild_status_idx
  on public.gacha_s2_guild_join_requests (guild_id, status);
create index if not exists gacha_s2_guild_join_requests_user_status_idx
  on public.gacha_s2_guild_join_requests (user_id, status);

-- 탈퇴·추방 후 재가입 제한(3일). 길드 이동으로 보상을 중복 수령하는 것을 막는다.
create table if not exists public.gacha_s2_guild_leave_penalties (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  left_at timestamptz not null default now(),
  penalty_until timestamptz not null,
  reason text not null check (reason in ('leave', 'kick')),
  check (penalty_until > left_at)
);

alter table public.gacha_s2_guild_emblems enable row level security;
alter table public.gacha_s2_guilds enable row level security;
alter table public.gacha_s2_guild_members enable row level security;
alter table public.gacha_s2_guild_join_requests enable row level security;
alter table public.gacha_s2_guild_leave_penalties enable row level security;

revoke all on table public.gacha_s2_guild_emblems from public, anon, authenticated;
revoke all on table public.gacha_s2_guilds from public, anon, authenticated;
revoke all on table public.gacha_s2_guild_members from public, anon, authenticated;
revoke all on table public.gacha_s2_guild_join_requests from public, anon, authenticated;
revoke all on table public.gacha_s2_guild_leave_penalties from public, anon, authenticated;
