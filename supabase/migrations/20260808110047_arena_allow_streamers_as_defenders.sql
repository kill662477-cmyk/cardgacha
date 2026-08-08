-- 투기장 상대 선정에서 스트리머를 빼던 조건을 없앤다.
-- 요청받은 적 없는 조건이 처음 구현 때 들어가 있었다(20260806005949_arena_match_rpcs.sql).
-- 그 결과 스트리머 계정 5개는 랭킹에는 나오면서 방어는 한 번도 당하지 않았다.
-- 공격만 하고 방어로 잃을 일이 없으니 구조적으로 유리했고, 1위 계정이 여기 해당했다.
-- 랭킹에 오르면 방어도 당하는 것이 맞다.
--
-- disabled_at 조건은 남긴다. 접속 금지된 계정이 방어자로 뽑히면 안 된다.
do $$
declare v_src text;
begin
  v_src := pg_get_functiondef('public.gacha_s2_arena_open_match(uuid,bigint,text)'::regprocedure);

  if v_src not like '%acc.is_streamer = false%' then
    raise exception 'streamer filter not found - already removed?';
  end if;

  v_src := replace(v_src, E'      and acc.is_streamer = false\n', '');

  if v_src like '%is_streamer%' then
    raise exception 'streamer filter still present after removal';
  end if;
  -- 나머지 조건은 그대로 남아 있어야 한다.
  if v_src not like '%acc.disabled_at is null%' then
    raise exception 'disabled filter was lost';
  end if;
  if v_src not like '%array_length(p.formation, 1) = 5%' then
    raise exception 'formation filter was lost';
  end if;
  if v_src not like '%abs(a.rating - v_self.rating) <= v_band%' then
    raise exception 'rating band filter was lost';
  end if;

  execute v_src;
end;
$$;

-- 이제 스트리머가 실제로 후보에 들어오는지 확인한다.
do $$
declare
  v_src text;
  v_candidates integer;
begin
  v_src := pg_get_functiondef('public.gacha_s2_arena_open_match(uuid,bigint,text)'::regprocedure);
  if v_src like '%is_streamer%' then
    raise exception 'streamer filter survived';
  end if;

  select count(*) into v_candidates
  from public.gacha_s2_arena_players a
  join public.gacha_s2_player_states p on p.user_id = a.user_id
  join public.gacha_s2_accounts acc on acc.id = a.user_id
  where acc.is_streamer = true
    and acc.disabled_at is null
    and p.formation is not null
    and array_length(p.formation, 1) = 5;
  raise notice 'streamer accounts now selectable as defenders: %', v_candidates;
end;
$$;
