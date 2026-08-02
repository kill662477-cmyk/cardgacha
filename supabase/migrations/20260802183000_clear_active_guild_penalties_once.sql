-- 2026-08-02 운영 1회 조치: 현재 활성 길드 탈퇴·추방 페널티 전원 해제.
-- 사전 읽기 전용 확인: 15명(leave 9, kick 6).
-- 이력 보존을 위해 행은 삭제하지 않고 만료 시각만 현재 시각으로 당긴다.
begin;

do $$
declare
  v_target integer;
  v_remaining integer;
begin
  select count(*) into v_target
  from public.gacha_s2_guild_leave_penalties
  where penalty_until > now();

  update public.gacha_s2_guild_leave_penalties
  set penalty_until = now()
  where penalty_until > now();

  select count(*) into v_remaining
  from public.gacha_s2_guild_leave_penalties
  where penalty_until > now();

  if v_remaining <> 0 then
    raise exception 'guild leave penalties still active: %', v_remaining;
  end if;

  raise notice 'cleared active guild penalties: %', v_target;
end;
$$;

commit;
