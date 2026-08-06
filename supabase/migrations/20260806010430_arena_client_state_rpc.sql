-- 클라이언트가 직접 부르는 투기장 상태 조회. 로또와 같은 방식으로 auth 세션에서 계정을 찾는다.
create or replace function public.gacha_s2_client_get_arena_state()
returns jsonb
language plpgsql
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
  v_state := public.gacha_s2_get_arena_state(v_user_id);
  return jsonb_build_object('ok', true, 'serverTime', public.gacha_s2_now_ms(), 'state', v_state);
end;
$$;

revoke all on function public.gacha_s2_client_get_arena_state() from public, anon;
grant execute on function public.gacha_s2_client_get_arena_state() to authenticated, service_role;
