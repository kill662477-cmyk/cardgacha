-- 투기장 확정이 감사 로그 제약(committed_revision = expected_revision + 1)을 위반해
-- 매치가 전부 pending 으로 남고 클라이언트에는 "요청 처리 실패"가 떴다.
-- 확정 단계가 리비전을 올리지 않고 같은 값을 두 번 넣은 것이 원인이다.
-- 레이팅이 실제로 바뀌므로 여기서 리비전을 올리는 것이 맞다.
do $$
declare v_src text;
begin
  v_src := pg_get_functiondef('public.gacha_s2_arena_commit_match(uuid,uuid,boolean,text,text)'::regprocedure);

  v_src := replace(
    v_src,
    'select revision into v_revision from public.gacha_s2_player_states where user_id = p_user_id;',
    'update public.gacha_s2_player_states set revision = revision + 1, updated_at = now()'
    || ' where user_id = p_user_id returning revision into v_revision;'
  );
  v_src := replace(
    v_src,
    'values (p_user_id, p_idempotency_key, ''arenaFight'', v_request_hash, v_revision, v_revision, v_seed)',
    'values (p_user_id, p_idempotency_key, ''arenaFight'', v_request_hash, v_revision - 1, v_revision, v_seed)'
  );

  if v_src not like '%v_revision - 1, v_revision, v_seed%' then
    raise exception 'audit revision fix not applied';
  end if;
  if v_src not like '%returning revision into v_revision%' then
    raise exception 'revision bump not applied';
  end if;
  execute v_src;
end;
$$;

-- 실패로 남은 대기 매치를 정리한다. 공격자는 행동력과 횟수를 이미 썼으므로 되돌려준다.
do $$
declare
  v_row record;
  v_cost integer;
  v_refunded integer := 0;
begin
  select coalesce((config->'arenaRules'->>'energyCost')::integer, 5) into v_cost
  from public.gacha_s2_balance_versions where active;

  update public.gacha_s2_arena_players a
  set week_attacks = greatest(0, a.week_attacks - pending.count), updated_at = now()
  from (
    select attacker_id, count(*)::integer as count
    from public.gacha_s2_arena_matches where status = 'pending' group by attacker_id
  ) pending
  where a.user_id = pending.attacker_id;

  for v_row in select match_id, attacker_id from public.gacha_s2_arena_matches where status = 'pending' loop
    update public.gacha_s2_player_states
    set action_energy = least(max_action_energy * 2, action_energy + v_cost),
        revision = revision + 1,
        updated_at = now()
    where user_id = v_row.attacker_id;
    v_refunded := v_refunded + 1;
  end loop;

  delete from public.gacha_s2_arena_matches where status = 'pending';
  raise notice 'refunded % stranded arena matches', v_refunded;
end;
$$;

do $$
declare v_pending integer;
begin
  select count(*) into v_pending from public.gacha_s2_arena_matches where status = 'pending';
  if v_pending > 0 then raise exception 'pending matches remain: %', v_pending; end if;
end;
$$;
