-- card-gacha 11차 마이그레이션: 방송인별 SOOP 브리지 키
-- 키 원문은 저장하지 않고 SHA-256 해시만 저장한다.

create table if not exists public.gacha_soop_bridge_keys (
  soop_id text primary key,
  key_hash text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

alter table public.gacha_soop_bridge_keys enable row level security;
