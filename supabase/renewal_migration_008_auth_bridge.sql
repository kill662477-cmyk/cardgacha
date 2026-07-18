-- Card Gacha Season 2: bind legacy login keys to Supabase Auth identities.
-- REVIEW ONLY. Run after migrations 001-007. Service role only.

begin;

alter table public.gacha_s2_accounts
  add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null,
  add column if not exists auth_bound_at timestamptz,
  add column if not exists last_auth_at timestamptz;

create index if not exists idx_gacha_s2_accounts_auth_user_id
  on public.gacha_s2_accounts(auth_user_id) where auth_user_id is not null;

create table if not exists public.gacha_s2_auth_rate_limits (
  rate_key text primary key check (rate_key ~ '^[0-9a-f]{64}$'),
  auth_user_id uuid not null,
  attempts integer not null default 0 check (attempts between 0 and 8),
  window_started_at timestamptz not null default now(),
  blocked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.gacha_s2_auth_rate_limits enable row level security;

create or replace function public.gacha_s2_bind_auth_session(
  p_auth_user_id uuid,
  p_login_key_hash text,
  p_rate_key text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit public.gacha_s2_auth_rate_limits%rowtype;
  v_account public.gacha_s2_accounts%rowtype;
  v_attempts integer;
begin
  if p_auth_user_id is null or p_login_key_hash !~ '^[0-9a-f]{64}$' or p_rate_key !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_REQUEST');
  end if;
  if not exists (select 1 from auth.users where id = p_auth_user_id) then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;

  select * into v_limit from public.gacha_s2_auth_rate_limits
  where rate_key = p_rate_key for update;
  if found and v_limit.blocked_until > now() then
    return jsonb_build_object(
      'ok', false, 'code', 'RATE_LIMITED',
      'retryAfterSeconds', greatest(1, ceil(extract(epoch from (v_limit.blocked_until - now())))::integer)
    );
  end if;
  if not found or v_limit.window_started_at < now() - interval '15 minutes' then
    insert into public.gacha_s2_auth_rate_limits (rate_key, auth_user_id, attempts, window_started_at, blocked_until, updated_at)
    values (p_rate_key, p_auth_user_id, 1, now(), null, now())
    on conflict (rate_key) do update set auth_user_id = excluded.auth_user_id, attempts = 1,
      window_started_at = now(), blocked_until = null, updated_at = now();
    v_attempts := 1;
  else
    v_attempts := v_limit.attempts + 1;
    update public.gacha_s2_auth_rate_limits
    set auth_user_id = p_auth_user_id,
        attempts = least(8, v_attempts),
        blocked_until = case when v_attempts >= 8 then now() + interval '15 minutes' else null end,
        updated_at = now()
    where rate_key = p_rate_key;
  end if;
  if v_attempts >= 8 then
    return jsonb_build_object('ok', false, 'code', 'RATE_LIMITED', 'retryAfterSeconds', 900);
  end if;

  select * into v_account
  from public.gacha_s2_accounts
  where login_key_hash = p_login_key_hash
  for update;
  if not found then
    perform pg_sleep(0.12);
    return jsonb_build_object('ok', false, 'code', 'INVALID_CREDENTIALS');
  end if;

  update public.gacha_s2_accounts
  set auth_user_id = null, auth_bound_at = null, updated_at = now()
  where auth_user_id = p_auth_user_id and id <> v_account.id;
  update public.gacha_s2_accounts
  set auth_user_id = p_auth_user_id,
      auth_bound_at = case when auth_user_id is distinct from p_auth_user_id then now() else auth_bound_at end,
      last_auth_at = now(),
      updated_at = now()
  where id = v_account.id;
  delete from public.gacha_s2_auth_rate_limits
  where rate_key = p_rate_key or auth_user_id = p_auth_user_id;

  return jsonb_build_object(
    'ok', true,
    'accountId', v_account.id,
    'nickname', v_account.nickname,
    'isStreamer', v_account.is_streamer
  );
end;
$$;

create or replace function public.gacha_s2_resolve_auth_account(p_auth_user_id uuid)
returns uuid
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select id from public.gacha_s2_accounts where auth_user_id = p_auth_user_id;
$$;

revoke all on table public.gacha_s2_auth_rate_limits from public, anon, authenticated;
revoke all on function public.gacha_s2_bind_auth_session(uuid, text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_resolve_auth_account(uuid) from public, anon, authenticated;
grant execute on function public.gacha_s2_bind_auth_session(uuid, text, text) to service_role;
grant execute on function public.gacha_s2_resolve_auth_account(uuid) to service_role;

commit;
