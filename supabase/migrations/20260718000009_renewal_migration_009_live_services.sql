-- Card Gacha Season 2: live ranking and SOOP donation services.
-- REVIEW ONLY. Run after migrations 001-008. Service role only.

begin;

do $$
begin
  if to_regprocedure('public.gacha_s2_get_player_snapshot(uuid)') is null
    or to_regclass('public.gacha_s2_streamer_bridges') is null then
    raise exception 'missing Season 2 schema: run migrations 001-008 first';
  end if;
end;
$$;

create table if not exists public.gacha_s2_soop_donation_events (
  event_id text primary key check (length(event_id) between 8 and 255),
  action text not null check (action in ('BALLOON_GIFTED', 'BATTLE_MISSION_GIFTED')),
  sender_soop_id text not null check (length(sender_soop_id) between 1 and 100),
  recipient_soop_id text not null check (length(recipient_soop_id) between 1 and 100),
  amount integer not null check (amount between 1 and 100000),
  points_per_account integer not null check (points_per_account > 0),
  sender_user_id uuid references public.gacha_s2_accounts(id) on delete set null,
  recipient_user_id uuid references public.gacha_s2_accounts(id) on delete set null,
  bridge_user_id uuid not null references public.gacha_s2_accounts(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.gacha_s2_bridge_rate_limits (
  rate_key text primary key check (rate_key ~ '^[0-9a-f]{64}$'),
  attempts integer not null default 0 check (attempts between 0 and 8),
  window_started_at timestamptz not null default now(),
  blocked_until timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.gacha_s2_soop_oauth_exchanges (
  exchange_hash text primary key check (exchange_hash ~ '^[0-9a-f]{64}$'),
  bridge_user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  soop_id text not null check (length(soop_id) between 1 and 100),
  access_token_ciphertext text not null,
  access_token_iv text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_gacha_s2_soop_events_recipient_created
  on public.gacha_s2_soop_donation_events(recipient_soop_id, created_at desc);

alter table public.gacha_s2_soop_donation_events enable row level security;
alter table public.gacha_s2_bridge_rate_limits enable row level security;
alter table public.gacha_s2_soop_oauth_exchanges enable row level security;

create or replace function public.gacha_s2_get_power_ranking(
  p_user_id uuid,
  p_verified_power integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rank integer;
  v_population integer;
  v_top_fifty_power integer := 0;
  v_leaders jsonb := '[]'::jsonb;
  v_nickname text;
begin
  if p_user_id is null or p_verified_power is null or p_verified_power < 0 or p_verified_power > 2000000000 then
    raise exception 'invalid power ranking input';
  end if;

  update public.gacha_s2_player_states
  set power_snapshot = p_verified_power,
      power_snapshot_at = now()
  where user_id = p_user_id;
  if not found then raise exception 'Season 2 account state not found'; end if;

  select nickname into v_nickname
  from public.gacha_s2_accounts
  where id = p_user_id;

  with ranked as (
    select state.user_id,
      account.nickname,
      state.power_snapshot,
      state.power_snapshot_at,
      state.representative_card_id,
      row_number() over (
        order by state.power_snapshot desc, state.power_snapshot_at asc nulls last, state.user_id
      )::integer as rank
    from public.gacha_s2_player_states state
    join public.gacha_s2_accounts account on account.id = state.user_id
  )
  select
    (select count(*)::integer from ranked),
    (select rank from ranked where user_id = p_user_id),
    coalesce((select power_snapshot from ranked where rank = 50), 0),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', rank,
        'nickname', nickname,
        'power', power_snapshot,
        'representativeCardId', representative_card_id,
        'mine', user_id = p_user_id
      ) order by rank)
      from ranked where rank <= 20
    ), '[]'::jsonb)
  into v_population, v_rank, v_top_fifty_power, v_leaders;

  return jsonb_build_object(
    'seasonId', 'season-2',
    'snapshotAt', public.gacha_s2_now_ms(),
    'population', v_population,
    'leaders', v_leaders,
    'topFiftyPower', v_top_fifty_power,
    'powerToTopFifty', case
      when v_rank <= 50 or v_top_fifty_power = 0 then 0
      else greatest(0, v_top_fifty_power - p_verified_power + 1)
    end,
    'player', jsonb_build_object(
      'nickname', v_nickname,
      'power', p_verified_power,
      'rank', v_rank,
      'topPercent', case when v_population = 0 then 100 else round(v_rank::numeric * 100 / v_population, 1) end
    )
  );
end;
$$;

create or replace function public.gacha_s2_get_bridge_status(p_user_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'canUseDonationBridge', account.is_streamer and bridge.active,
    'soopId', case when account.is_streamer and bridge.active then bridge.soop_id else null end
  )
  from public.gacha_s2_accounts account
  left join public.gacha_s2_streamer_bridges bridge on bridge.user_id = account.id
  where account.id = p_user_id;
$$;

create or replace function public.gacha_s2_authenticate_streamer_bridge(p_key_hash text, p_rate_key text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_bridge public.gacha_s2_streamer_bridges%rowtype;
  v_limit public.gacha_s2_bridge_rate_limits%rowtype;
  v_attempts integer;
begin
  if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$'
    or p_rate_key is null or p_rate_key !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_REQUEST');
  end if;
  select * into v_limit from public.gacha_s2_bridge_rate_limits where rate_key = p_rate_key for update;
  if found and v_limit.blocked_until > now() then
    return jsonb_build_object('ok', false, 'code', 'RATE_LIMITED',
      'retryAfterSeconds', greatest(1, ceil(extract(epoch from (v_limit.blocked_until - now())))::integer));
  end if;
  if not found or v_limit.window_started_at < now() - interval '15 minutes' then
    insert into public.gacha_s2_bridge_rate_limits (rate_key, attempts, window_started_at, blocked_until, updated_at)
    values (p_rate_key, 1, now(), null, now())
    on conflict (rate_key) do update set attempts = 1, window_started_at = now(), blocked_until = null, updated_at = now();
    v_attempts := 1;
  else
    v_attempts := v_limit.attempts + 1;
    update public.gacha_s2_bridge_rate_limits
    set attempts = least(8, v_attempts),
        blocked_until = case when v_attempts >= 8 then now() + interval '15 minutes' else null end,
        updated_at = now()
    where rate_key = p_rate_key;
  end if;
  if v_attempts >= 8 then
    return jsonb_build_object('ok', false, 'code', 'RATE_LIMITED', 'retryAfterSeconds', 900);
  end if;
  select * into v_bridge
  from public.gacha_s2_streamer_bridges
  where key_hash = p_key_hash and active
  for update;
  if not found then
    perform pg_sleep(0.12);
    return jsonb_build_object('ok', false, 'code', 'INVALID_CREDENTIALS');
  end if;
  update public.gacha_s2_streamer_bridges
  set last_used_at = now(), updated_at = now()
  where user_id = v_bridge.user_id;
  delete from public.gacha_s2_bridge_rate_limits where rate_key = p_rate_key;
  return jsonb_build_object('ok', true, 'userId', v_bridge.user_id, 'soopId', v_bridge.soop_id);
end;
$$;

create or replace function public.gacha_s2_consume_soop_exchange(
  p_bridge_user_id uuid,
  p_exchange_hash text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_exchange public.gacha_s2_soop_oauth_exchanges%rowtype;
begin
  if p_bridge_user_id is null or p_exchange_hash is null or p_exchange_hash !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select * into v_exchange
  from public.gacha_s2_soop_oauth_exchanges
  where exchange_hash = p_exchange_hash and bridge_user_id = p_bridge_user_id
  for update;
  if not found or v_exchange.consumed_at is not null or v_exchange.expires_at <= now() then return null; end if;
  update public.gacha_s2_soop_oauth_exchanges set consumed_at = now() where exchange_hash = p_exchange_hash;
  return jsonb_build_object(
    'soopId', v_exchange.soop_id,
    'ciphertext', v_exchange.access_token_ciphertext,
    'iv', v_exchange.access_token_iv
  );
end;
$$;

create or replace function public.gacha_s2_apply_soop_donation(
  p_bridge_user_id uuid,
  p_event_id text,
  p_action text,
  p_sender_soop_id text,
  p_recipient_soop_id text,
  p_amount integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing public.gacha_s2_soop_donation_events%rowtype;
  v_sender_user uuid;
  v_recipient_user uuid;
  v_points integer;
begin
  if p_bridge_user_id is null
    or p_event_id is null or length(trim(p_event_id)) < 8 or length(trim(p_event_id)) > 255
    or p_action is null or p_action not in ('BALLOON_GIFTED', 'BATTLE_MISSION_GIFTED')
    or p_sender_soop_id is null or length(trim(p_sender_soop_id)) < 1 or length(trim(p_sender_soop_id)) > 100
    or p_recipient_soop_id is null or length(trim(p_recipient_soop_id)) < 1 or length(trim(p_recipient_soop_id)) > 100
    or p_amount is null or p_amount < 1 or p_amount > 100000 then
    raise exception 'invalid donation input';
  end if;
  if not exists (
    select 1 from public.gacha_s2_streamer_bridges bridge
    where bridge.user_id = p_bridge_user_id
      and bridge.soop_id = trim(p_recipient_soop_id)
      and bridge.active
  ) then
    raise exception 'bridge recipient mismatch';
  end if;

  perform pg_advisory_xact_lock(hashtext('gacha_s2_soop:' || p_event_id));
  perform pg_advisory_xact_lock(hashtext('gacha_s2_soop_user:' || least(p_sender_soop_id, p_recipient_soop_id)));
  if p_sender_soop_id <> p_recipient_soop_id then
    perform pg_advisory_xact_lock(hashtext('gacha_s2_soop_user:' || greatest(p_sender_soop_id, p_recipient_soop_id)));
  end if;
  select * into v_existing
  from public.gacha_s2_soop_donation_events
  where event_id = p_event_id;
  if found then
    if v_existing.action <> p_action
      or v_existing.sender_soop_id <> trim(p_sender_soop_id)
      or v_existing.recipient_soop_id <> trim(p_recipient_soop_id)
      or v_existing.amount <> p_amount then
      raise exception 'donation event id reused with different payload';
    end if;
    return jsonb_build_object('applied', false, 'pointsPerAccount', v_existing.points_per_account);
  end if;

  v_points := p_amount * 3;
  select id into v_sender_user from public.gacha_s2_accounts where soop_id = trim(p_sender_soop_id);
  select id into v_recipient_user from public.gacha_s2_accounts where soop_id = trim(p_recipient_soop_id);

  if v_sender_user is not null and v_sender_user = v_recipient_user then
    update public.gacha_s2_player_states
    set points = points + v_points * 2, revision = revision + 1, updated_at = now()
    where user_id = v_sender_user;
  else
    if v_sender_user is not null then
      update public.gacha_s2_player_states
      set points = points + v_points, revision = revision + 1, updated_at = now()
      where user_id = v_sender_user;
    end if;
    if v_recipient_user is not null then
      update public.gacha_s2_player_states
      set points = points + v_points, revision = revision + 1, updated_at = now()
      where user_id = v_recipient_user;
    end if;
  end if;

  insert into public.gacha_s2_soop_donation_events (
    event_id, action, sender_soop_id, recipient_soop_id, amount, points_per_account,
    sender_user_id, recipient_user_id, bridge_user_id
  ) values (
    trim(p_event_id), p_action, trim(p_sender_soop_id), trim(p_recipient_soop_id), p_amount, v_points,
    v_sender_user, v_recipient_user, p_bridge_user_id
  );
  return jsonb_build_object(
    'applied', true,
    'pointsPerAccount', v_points,
    'senderCredited', v_sender_user is not null,
    'recipientCredited', v_recipient_user is not null
  );
end;
$$;

revoke all on table public.gacha_s2_soop_donation_events from public, anon, authenticated;
revoke all on table public.gacha_s2_bridge_rate_limits from public, anon, authenticated;
revoke all on table public.gacha_s2_soop_oauth_exchanges from public, anon, authenticated;
revoke all on function public.gacha_s2_get_power_ranking(uuid, integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_get_bridge_status(uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_authenticate_streamer_bridge(text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_consume_soop_exchange(uuid, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_apply_soop_donation(uuid, text, text, text, text, integer) from public, anon, authenticated;

grant execute on function public.gacha_s2_get_power_ranking(uuid, integer) to service_role;
grant execute on function public.gacha_s2_get_bridge_status(uuid) to service_role;
grant execute on function public.gacha_s2_authenticate_streamer_bridge(text, text) to service_role;
grant execute on function public.gacha_s2_consume_soop_exchange(uuid, text) to service_role;
grant execute on function public.gacha_s2_apply_soop_donation(uuid, text, text, text, text, integer) to service_role;

commit;
