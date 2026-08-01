-- 운영 조치: 2026-08-01 기준 진행 중인 길드 재가입 제한(3일)을 전원 즉시 해제한다.
-- 대상 44명(탈퇴 26 / 추방 18). 만료일이 최대 08-04 20:10 까지 남아 있었다.
--
-- 행을 지우지 않고 penalty_until 만 now() 로 당긴다.
-- 제한 판정은 gacha_s2_request_join_guild / gacha_s2_get_guild_overview 양쪽 모두
-- "penalty_until > now()" 한 가지 조건이라 이것만으로 완전히 풀린다.
-- left_at 과 reason 을 남겨야 누가 언제 왜 나갔는지 추적이 남는다(테이블 PK 가 user_id 라
-- 행을 지우면 그 기록이 사라진다).
update public.gacha_s2_guild_leave_penalties
set penalty_until = now()
where penalty_until > now();

do $$
declare v_active integer;
begin
  select count(*) into v_active
  from public.gacha_s2_guild_leave_penalties
  where penalty_until > now();
  if v_active > 0 then
    raise exception 'guild leave penalties still active: %', v_active;
  end if;
end;
$$;
