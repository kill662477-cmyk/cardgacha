-- 인증 사용자의 조회 전용 요청을 Edge Function에서 PostgREST RPC로 이동한다.
-- 클라이언트는 user_id를 전달하지 못하며 auth.uid()에 연결된 계정만 조회한다.

begin;

create or replace function public.gacha_s2_client_account_id()
returns uuid
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select account.id
  from public.gacha_s2_accounts account
  where account.auth_user_id = auth.uid();
$$;

create or replace function public.gacha_s2_client_get_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user_id uuid := public.gacha_s2_client_account_id();
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;
  return jsonb_build_object(
    'ok', true,
    'serverTime', public.gacha_s2_now_ms(),
    'snapshot', public.gacha_s2_get_player_snapshot(v_user_id)
  );
end;
$$;

create or replace function public.gacha_s2_client_get_world_boss_status(
  p_event_id text default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user_id uuid := public.gacha_s2_client_account_id();
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;
  if p_event_id is not null and length(p_event_id) > 100 then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_FAILED');
  end if;
  return jsonb_build_object(
    'ok', true,
    'serverTime', public.gacha_s2_now_ms(),
    'status', public.gacha_s2_get_world_boss_status(v_user_id, p_event_id)
  );
end;
$$;

create or replace function public.gacha_s2_client_get_lotto_state()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user_id uuid := public.gacha_s2_client_account_id();
  v_state jsonb;
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;
  v_state := public.gacha_s2_get_lotto_state_v2(v_user_id);
  if v_state->>'ok' = 'false' then return v_state; end if;
  return jsonb_build_object(
    'ok', true,
    'serverTime', public.gacha_s2_now_ms(),
    'state', v_state
  );
end;
$$;

create or replace function public.gacha_s2_client_get_guild_state(
  p_guild_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user_id uuid := public.gacha_s2_client_account_id();
  v_state jsonb;
  v_personal jsonb;
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;
  v_state := public.gacha_s2_get_guild_state(v_user_id, p_guild_id);
  if jsonb_typeof(v_state->'weekly') = 'object'
    and jsonb_typeof(v_state->'membership') = 'object'
  then
    v_personal := public.gacha_s2_get_guild_weekly_member_progress(v_user_id);
    v_state := jsonb_set(
      v_state,
      '{weekly,myContributions}',
      coalesce(v_personal->'goals', '[]'::jsonb),
      true
    );
  end if;
  return jsonb_build_object(
    'ok', true,
    'serverTime', public.gacha_s2_now_ms(),
    'state', v_state
  );
end;
$$;

create or replace function public.gacha_s2_client_get_guild_raid_status()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user_id uuid := public.gacha_s2_client_account_id();
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;
  return jsonb_build_object(
    'ok', true,
    'serverTime', public.gacha_s2_now_ms(),
    'status', public.gacha_s2_get_guild_raid_status(v_user_id)
  );
end;
$$;

create or replace function public.gacha_s2_client_get_bridge_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user_id uuid := public.gacha_s2_client_account_id();
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;
  return jsonb_build_object(
    'ok', true,
    'serverTime', public.gacha_s2_now_ms(),
    'status', coalesce(
      public.gacha_s2_get_bridge_status(v_user_id),
      jsonb_build_object('canUseDonationBridge', false, 'soopId', null)
    )
  );
end;
$$;

create or replace function public.gacha_s2_client_get_mailbox(
  p_limit integer default 50
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user_id uuid := public.gacha_s2_client_account_id();
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;
  return jsonb_build_object(
    'ok', true,
    'serverTime', public.gacha_s2_now_ms(),
    'mailbox', public.gacha_s2_get_mailbox(v_user_id, p_limit)
  );
end;
$$;

revoke all on function public.gacha_s2_client_account_id()
  from public, anon, authenticated;
revoke all on function public.gacha_s2_client_get_snapshot()
  from public, anon, authenticated;
revoke all on function public.gacha_s2_client_get_world_boss_status(text)
  from public, anon, authenticated;
revoke all on function public.gacha_s2_client_get_lotto_state()
  from public, anon, authenticated;
revoke all on function public.gacha_s2_client_get_guild_state(uuid)
  from public, anon, authenticated;
revoke all on function public.gacha_s2_client_get_guild_raid_status()
  from public, anon, authenticated;
revoke all on function public.gacha_s2_client_get_bridge_status()
  from public, anon, authenticated;
revoke all on function public.gacha_s2_client_get_mailbox(integer)
  from public, anon, authenticated;

grant execute on function public.gacha_s2_client_get_snapshot()
  to authenticated;
grant execute on function public.gacha_s2_client_get_world_boss_status(text)
  to authenticated;
grant execute on function public.gacha_s2_client_get_lotto_state()
  to authenticated;
grant execute on function public.gacha_s2_client_get_guild_state(uuid)
  to authenticated;
grant execute on function public.gacha_s2_client_get_guild_raid_status()
  to authenticated;
grant execute on function public.gacha_s2_client_get_bridge_status()
  to authenticated;
grant execute on function public.gacha_s2_client_get_mailbox(integer)
  to authenticated;

do $verify$
begin
  if to_regprocedure('public.gacha_s2_client_get_snapshot()') is null
    or to_regprocedure('public.gacha_s2_client_get_world_boss_status(text)') is null
    or to_regprocedure('public.gacha_s2_client_get_lotto_state()') is null
    or to_regprocedure('public.gacha_s2_client_get_guild_state(uuid)') is null
    or to_regprocedure('public.gacha_s2_client_get_guild_raid_status()') is null
    or to_regprocedure('public.gacha_s2_client_get_bridge_status()') is null
    or to_regprocedure('public.gacha_s2_client_get_mailbox(integer)') is null
  then
    raise exception 'authenticated read API installation failed';
  end if;
end
$verify$;

commit;
