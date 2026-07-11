-- card-gacha DB 마이그레이션
-- Supabase 콘솔 > SQL Editor 에 붙여넣고 실행하세요.
-- 정책(policy)을 만들지 않으므로 RLS 가 anon 접근을 전면 차단합니다.
-- 서버리스 함수의 service_role 키만 통과합니다.

create table if not exists gacha_users (
  id uuid primary key default gen_random_uuid(),
  nickname text not null,
  login_key text unique not null,
  points int not null default 1000,
  last_attend date,
  created_at timestamptz default now()
);

create table if not exists gacha_collection (
  user_id uuid references gacha_users(id) on delete cascade,
  card_id text not null,
  count int not null default 1,
  first_at timestamptz default now(),
  primary key (user_id, card_id)
);

-- UR 이상 레어 드랍 전체 공지 티커용
create table if not exists gacha_announcements (
  id bigint generated always as identity primary key,
  nickname text not null,
  member text not null,
  card_id text not null,
  rarity text not null,
  created_at timestamptz default now()
);

alter table gacha_users enable row level security;
alter table gacha_collection enable row level security;
alter table gacha_announcements enable row level security;

-- (정책 미생성 = anon 전면 차단, service_role 만 통과)
