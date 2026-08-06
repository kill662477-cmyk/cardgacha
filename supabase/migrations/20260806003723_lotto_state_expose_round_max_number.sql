-- 로또 상태에 회차별 번호 상한(maxNumber)을 실어 보낸다.
-- 클라이언트가 상수 대신 이 값으로 번호판을 그려야, 1~18 로 팔린 진행 중 회차는
-- 18칸 그대로 두고 다음 회차부터 16칸이 된다.
do $$
declare
  v_src text;
  v_anchor text := '''ticketCount'', v_round.ticket_count';
begin
  v_src := pg_get_functiondef('public.gacha_s2_get_lotto_state(uuid)'::regprocedure);
  if position(v_anchor in v_src) = 0 then
    raise exception 'round payload anchor not found in lotto state function';
  end if;
  if position('''maxNumber''' in v_src) > 0 then
    raise exception 'maxNumber already present';
  end if;
  v_src := replace(v_src, v_anchor, v_anchor || ',' || chr(10) || '      ''maxNumber'', v_round.max_number');
  execute v_src;
end;
$$;

do $$
declare
  v_state jsonb;
  v_max integer;
begin
  select public.gacha_s2_get_lotto_state(user_id) into v_state
  from public.gacha_s2_player_states limit 1;
  v_max := (v_state->'round'->>'maxNumber')::integer;
  if v_max is null then
    raise exception 'maxNumber missing from lotto state round payload';
  end if;
  -- 지금 열린 회차는 1~18 로 팔렸으니 18 이어야 한다.
  if v_max <> 18 then
    raise exception 'open round exposes maxNumber %, expected 18', v_max;
  end if;
end;
$$;
