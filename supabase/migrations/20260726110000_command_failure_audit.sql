-- Persist failed Edge requests outside command transactions.
-- Payloads and credentials are intentionally not stored.

begin;

create table if not exists public.gacha_s2_command_failures (
  id bigint generated always as identity primary key,
  request_id uuid not null,
  auth_user_id uuid,
  user_id uuid references public.gacha_s2_accounts(id) on delete set null,
  request_kind text not null,
  command_id text,
  command_type text,
  error_code text not null,
  http_status smallint not null check (http_status between 400 and 599),
  error_source text not null,
  error_message text,
  created_at timestamptz not null default now(),
  unique (request_id)
);

create index if not exists idx_gacha_s2_command_failures_created
  on public.gacha_s2_command_failures(created_at desc);

create index if not exists idx_gacha_s2_command_failures_user_created
  on public.gacha_s2_command_failures(user_id, created_at desc);

alter table public.gacha_s2_command_failures enable row level security;
revoke all on table public.gacha_s2_command_failures from public, anon, authenticated;
revoke all on sequence public.gacha_s2_command_failures_id_seq from public, anon, authenticated;

commit;
