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

  select * into v_exchange
  from public.gacha_s2_soop_auth_exchanges
  where exchange_hash = encode(digest(p_exchange_code, 'sha256'), 'hex')
  for update;
  if not found or v_exchange.consumed_at is not null or v_exchange.expires_at <= now() then
    perform pg_sleep(0.12);
    return jsonb_build_object('ok', false, 'code', 'INVALID_CREDENTIALS');
  end if;

  select * into v_account
  from public.gacha_s2_accounts
  where soop_id = v_exchange.soop_id
  for update;

  v_nickname := public.gacha_s2_safe_nickname(v_exchange.nickname, v_exchange.soop_id);

  if not found then
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
    if v_account.nickname is distinct from v_nickname then
      update public.gacha_s2_accounts
      set nickname = v_nickname, updated_at = now()
      where id = v_account.id
      returning * into v_account;
    end if;
  end if;

  update public.gacha_s2_soop_auth_exchanges
  set consumed_at = now()
  where exchange_hash = v_exchange.exchange_hash and consumed_at is null;

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
