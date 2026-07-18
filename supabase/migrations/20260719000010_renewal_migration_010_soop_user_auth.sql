-- Card Gacha Season 2: restore SOOP user login (general users, not streamer bridge).
-- REVIEW ONLY. Run after migrations 001-009. Service role only.
--
-- 시즌2를 Supabase 기반으로 전환하면서 일반 유저 SOOP 숲 로그인이 빠져 있던 것을 복구.
-- soop-auth Edge Function이 OAuth 콜백에서 access_token을 암호화해 이 테이블에 임시 저장하고,
-- 클라이언트가 받은 일회성 exchange 코드로 gacha_s2_bind_soop_session RPC를 호출하면
-- soop_id 기반으로 기존 계정을 매칭하거나 신규 생성하고 Supabase Auth 세션을 바인딩한다.
--
-- 스트리머 후원 브릿지용 gacha_s2_soop_oauth_exchanges(bridge_user_id NOT NULL)와는 별개 테이블.

begin;

-- 일반 유저 SOOP OAuth exchange 임시 저장. bridge_user_id 제약 없음(아직 account가 없을 수 있음).
create table if not exists public.gacha_s2_soop_auth_exchanges (
  exchange_hash text primary key check (exchange_hash ~ '^[0-9a-f]{64}$'),
  soop_id text not null check (length(soop_id) between 1 and 100),
  nickname text not null check (length(trim(nickname)) between 1 and 40),
  access_token_ciphertext text not null,
  access_token_iv text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.gacha_s2_soop_auth_exchanges enable row level security;

create index if not exists idx_gacha_s2_soop_auth_exchanges_expires
  on public.gacha_s2_soop_auth_exchanges(expires_at);

-- 콜백 폭주 방지용 IP rate 로그. rate_key = HMAC-SHA256(ip, AUTH_RATE_LIMIT_PEPPER).
-- 분당 20회 초과 시 콜백을 거부한다(시즌1 정책과 동일).
create table if not exists public.gacha_s2_soop_auth_rate_log (
  id bigint generated always as identity primary key,
  rate_key text not null check (rate_key ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);
alter table public.gacha_s2_soop_auth_rate_log enable row level security;
create index if not exists idx_gacha_s2_soop_auth_rate_log_key_created
  on public.gacha_s2_soop_auth_rate_log(rate_key, created_at desc);

-- nickname 파생: stationinfo user_nick 이 비정상이면 soop_id로 폴백. accounts.nickname CHECK(1~40) 만족용.
create or replace function public.gacha_s2_safe_nickname(p_nick text, p_soop_id text)
returns text
language sql
immutable
as $$
  select case
    when length(trim(p_nick)) between 1 and 40 then trim(p_nick)
    when length(trim(p_soop_id)) between 1 and 40 then trim(p_soop_id)
    else left(trim(p_soop_id), 40)
  end;
$$;

-- 일반 숲 유저용 deterministic login_key_hash 더미값. accounts.login_key_hash는 NOT NULL unique.
-- 실제 login_key 인증 경로(sha256(원문키))와 절대 충돌하지 않는 네임스페이스 프리픽스를 붙인다.
-- 해시 알고리즘은 다른 migration과 동일하게 pgcrypto digest(sha256) 사용.
create or replace function public.gacha_s2_soop_login_key_hash(p_soop_id text)
returns text
language sql
immutable
as $$
  select encode(digest('soop-only:' || trim(p_soop_id), 'sha256'), 'hex');
$$;

-- 일반 유저 SOOP 세션 바인딩. login_key 기반 gacha_s2_bind_auth_session 과 동일한 구조/보장.
-- exchange 코드 -> soop_id 확정 -> 계정 매칭(없으면 신규 생성) -> auth_user_id 바인딩 -> exchange consume.
create or replace function public.gacha_s2_bind_soop_session(
  p_auth_user_id uuid,
  p_exchange_code text,
  p_rate_key text,
  p_nickname_hint text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit public.gacha_s2_auth_rate_limits%rowtype;
  v_exchange public.gacha_s2_soop_auth_exchanges%rowtype;
  v_account public.gacha_s2_accounts%rowtype;
  v_attempts integer;
  v_nickname text;
  v_is_new boolean := false;
begin
  if p_auth_user_id is null
    or p_exchange_code is null
    or p_rate_key is null or p_rate_key !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_REQUEST');
  end if;
  if not exists (select 1 from auth.users where id = p_auth_user_id) then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;

  -- rate limit (gacha_s2_auth_rate_limits 재사용). login_key 바인딩과 동일 정책.
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

  -- exchange 코드 조회 (행잠금). 만료/소비됐으면 타이밍 공격 완화용 대기 후 실패.
  select * into v_exchange
  from public.gacha_s2_soop_auth_exchanges
  where exchange_hash = encode(digest(p_exchange_code, 'sha256'), 'hex')
  for update;
  if not found or v_exchange.consumed_at is not null or v_exchange.expires_at <= now() then
    perform pg_sleep(0.12);
    return jsonb_build_object('ok', false, 'code', 'INVALID_CREDENTIALS');
  end if;

  -- soop_id로 계정 매칭.
  select * into v_account
  from public.gacha_s2_accounts
  where soop_id = v_exchange.soop_id
  for update;

  v_nickname := public.gacha_s2_safe_nickname(v_exchange.nickname, v_exchange.soop_id);

  if not found then
    -- 신규 숲 유저: accounts + player_states 동시 생성(단일 트랜잭션).
    -- login_key_hash는 NOT NULL unique 인데 일반 숲 유저는 key가 없으므로,
    -- soop_id 기반 deterministic 더미 해시를 넣는다(실제 login_key 인증 경로와 충돌하지 않는 네임스페이스).
    insert into public.gacha_s2_accounts (nickname, login_key_hash, soop_id, is_streamer)
    values (
      v_nickname,
      public.gacha_s2_soop_login_key_hash(v_exchange.soop_id),
      v_exchange.soop_id,
      coalesce((
        select exists (
          select 1 from public.gacha_s2_streamer_bridges bridge
          where bridge.soop_id = v_exchange.soop_id and bridge.active
        )
      ), false)
    )
    on conflict (soop_id) do update
      set nickname = excluded.nickname, updated_at = now()
    returning * into v_account;

    insert into public.gacha_s2_player_states (user_id)
    values (v_account.id)
    on conflict (user_id) do nothing;

    v_is_new := true;
  else
    -- 기존 계정: 닉네임 갱신(SOOP 최신 user_nick 반영).
    update public.gacha_s2_accounts
    set nickname = v_nickname, updated_at = now()
    where id = v_account.id and nickname is distinct from v_nickname
    returning * into v_account;
  end if;

  -- exchange 코드 단일 소비 (재사용 방지).
  update public.gacha_s2_soop_auth_exchanges
  set consumed_at = now()
  where exchange_hash = v_exchange.exchange_hash and consumed_at is null;

  -- 동일 auth_user_id가 다른 계정에 묶여 있으면 해제, 현재 계정에 바인딩.
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
    'isStreamer', v_account.is_streamer,
    'isNew', v_is_new
  );
end;
$$;

revoke all on table public.gacha_s2_soop_auth_exchanges from public, anon, authenticated;
revoke all on table public.gacha_s2_soop_auth_rate_log from public, anon, authenticated;
revoke all on function public.gacha_s2_safe_nickname(text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_soop_login_key_hash(text) from public, anon, authenticated;
revoke all on function public.gacha_s2_bind_soop_session(uuid, text, text, text) from public, anon, authenticated;
grant select, insert, update on table public.gacha_s2_soop_auth_exchanges to service_role;
grant select, insert on table public.gacha_s2_soop_auth_rate_log to service_role;
grant execute on function public.gacha_s2_safe_nickname(text, text) to service_role;
grant execute on function public.gacha_s2_soop_login_key_hash(text) to service_role;
grant execute on function public.gacha_s2_bind_soop_session(uuid, text, text, text) to service_role;

commit;
