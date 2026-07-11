-- Security hardening: run this in Supabase SQL Editor before deploying API changes.
create extension if not exists pgcrypto;

alter table public.gacha_users add column if not exists login_key_hash text;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'gacha_users' and column_name = 'login_key'
  ) then
    update public.gacha_users
    set login_key_hash = encode(digest(login_key, 'sha256'), 'hex')
    where login_key_hash is null;
    alter table public.gacha_users drop column login_key;
  end if;
end $$;

alter table public.gacha_users alter column login_key_hash set not null;
create unique index if not exists gacha_users_login_key_hash_key
  on public.gacha_users(login_key_hash);

create table if not exists public.gacha_rate_limits (
  bucket text primary key,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0)
);
alter table public.gacha_rate_limits enable row level security;

create or replace function public.gacha_take_rate_limit(
  p_bucket text,
  p_limit integer,
  p_window_seconds integer
) returns table(allowed boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.gacha_rate_limits%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if length(p_bucket) < 1 or p_limit < 1 or p_limit > 10000
    or p_window_seconds < 1 or p_window_seconds > 86400 then
    raise exception 'invalid rate limit input';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_bucket, 0));
  select * into v_row from public.gacha_rate_limits where bucket = p_bucket for update;

  if not found then
    insert into public.gacha_rate_limits(bucket, window_started_at, request_count)
    values (p_bucket, v_now, 1);
    return query select true;
  elsif v_row.window_started_at + make_interval(secs => p_window_seconds) <= v_now then
    update public.gacha_rate_limits
    set window_started_at = v_now, request_count = 1
    where bucket = p_bucket;
    return query select true;
  elsif v_row.request_count >= p_limit then
    return query select false;
  else
    update public.gacha_rate_limits set request_count = request_count + 1 where bucket = p_bucket;
    return query select true;
  end if;
end;
$$;

create or replace function public.gacha_open_pack(
  p_user_id uuid,
  p_price integer,
  p_score_gain integer,
  p_gains jsonb
) returns table(points integer, ranking_score integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user public.gacha_users%rowtype;
  v_card_id text;
  v_delta_text text;
  v_delta integer;
begin
  if p_price < 1 or p_score_gain < 0 or jsonb_typeof(p_gains) <> 'object' then
    raise exception 'invalid pack input';
  end if;

  select * into v_user from public.gacha_users where id = p_user_id for update;
  if not found then raise exception 'user not found'; end if;
  if v_user.points < p_price then raise exception 'insufficient points' using errcode = 'P0001'; end if;

  for v_card_id, v_delta_text in select key, value from jsonb_each_text(p_gains) loop
    v_delta := v_delta_text::integer;
    if v_delta < 1 then raise exception 'invalid card gain'; end if;
    insert into public.gacha_collection(user_id, card_id, count)
    values (p_user_id, v_card_id, v_delta)
    on conflict (user_id, card_id) do update
    set count = public.gacha_collection.count + excluded.count;
  end loop;

  return query
  update public.gacha_users
  set points = public.gacha_users.points - p_price,
      ranking_score = coalesce(public.gacha_users.ranking_score, 0) + p_score_gain
  where id = p_user_id
  returning public.gacha_users.points, public.gacha_users.ranking_score;
end;
$$;

create or replace function public.gacha_claim_attendance(
  p_user_id uuid,
  p_today date,
  p_yesterday date,
  p_base integer,
  p_streak_bonus integer,
  p_newbie_bonus integer
) returns table(points integer, attended boolean, bonus integer, streak integer, newbie boolean, next_bonus_in integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user public.gacha_users%rowtype;
  v_streak integer;
  v_bonus integer;
  v_newbie boolean := false;
begin
  select * into v_user from public.gacha_users where id = p_user_id for update;
  if not found then raise exception 'user not found'; end if;

  if v_user.last_attend = p_today then
    return query select v_user.points, false, 0, coalesce(v_user.streak, 0), false, 0;
    return;
  end if;

  v_streak := case when v_user.last_attend = p_yesterday then coalesce(v_user.streak, 0) + 1 else 1 end;
  v_bonus := case when v_streak % 7 = 0 then p_streak_bonus else p_base end;
  if v_user.created_at >= clock_timestamp() - interval '7 days' then
    v_bonus := v_bonus + p_newbie_bonus;
    v_newbie := true;
  end if;

  return query
  update public.gacha_users
  set points = public.gacha_users.points + v_bonus, last_attend = p_today, streak = v_streak
  where id = p_user_id
  returning public.gacha_users.points, true, v_bonus, v_streak, v_newbie,
    case when (7 - (v_streak % 7)) % 7 = 0 then 7 else (7 - (v_streak % 7)) % 7 end;
end;
$$;

create or replace function public.gacha_dismantle(
  p_user_id uuid,
  p_updates jsonb
) returns table(points integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user public.gacha_users%rowtype;
  v_item record;
  v_actual integer;
  v_total integer := 0;
begin
  if jsonb_typeof(p_updates) <> 'array' or jsonb_array_length(p_updates) < 1 then
    raise exception 'invalid dismantle input';
  end if;

  select * into v_user from public.gacha_users where id = p_user_id for update;
  if not found then raise exception 'user not found'; end if;

  for v_item in
    select * from jsonb_to_recordset(p_updates)
      as x(card_id text, expected_count integer, new_count integer, refund integer)
  loop
    if v_item.card_id is null or v_item.expected_count is null or v_item.new_count is null or v_item.refund is null
      or v_item.expected_count < 2 or v_item.new_count < 1 or v_item.new_count >= v_item.expected_count or v_item.refund < 0 then
      raise exception 'invalid dismantle input';
    end if;
    select count into v_actual from public.gacha_collection
    where user_id = p_user_id and card_id = v_item.card_id for update;
    if not found or v_actual <> v_item.expected_count then
      raise exception 'state changed' using errcode = 'P0001';
    end if;
    update public.gacha_collection set count = v_item.new_count
    where user_id = p_user_id and card_id = v_item.card_id;
    v_total := v_total + v_item.refund;
  end loop;

  return query
  update public.gacha_users set points = public.gacha_users.points + v_total where id = p_user_id
  returning public.gacha_users.points;
end;
$$;

create or replace function public.gacha_claim_reward(
  p_user_id uuid,
  p_member text,
  p_reward integer,
  p_ranking_bonus integer
) returns table(claimed boolean, points integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user public.gacha_users%rowtype;
  v_inserted integer;
begin
  if p_reward < 0 or p_ranking_bonus < 0 then raise exception 'invalid reward input'; end if;
  select * into v_user from public.gacha_users where id = p_user_id for update;
  if not found then raise exception 'user not found'; end if;

  insert into public.gacha_member_rewards(user_id, member)
  values (p_user_id, p_member)
  on conflict (user_id, member) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return query select false, v_user.points;
    return;
  end if;

  return query
  update public.gacha_users
  set points = public.gacha_users.points + p_reward,
      ranking_score = coalesce(public.gacha_users.ranking_score, 0) + p_ranking_bonus
  where id = p_user_id
  returning true, public.gacha_users.points;
end;
$$;

revoke all on function public.gacha_take_rate_limit(text, integer, integer) from public;
revoke all on function public.gacha_open_pack(uuid, integer, integer, jsonb) from public;
revoke all on function public.gacha_claim_attendance(uuid, date, date, integer, integer, integer) from public;
revoke all on function public.gacha_dismantle(uuid, jsonb) from public;
revoke all on function public.gacha_claim_reward(uuid, text, integer, integer) from public;
grant execute on function public.gacha_take_rate_limit(text, integer, integer) to service_role;
grant execute on function public.gacha_open_pack(uuid, integer, integer, jsonb) to service_role;
grant execute on function public.gacha_claim_attendance(uuid, date, date, integer, integer, integer) to service_role;
grant execute on function public.gacha_dismantle(uuid, jsonb) to service_role;
grant execute on function public.gacha_claim_reward(uuid, text, integer, integer) to service_role;
