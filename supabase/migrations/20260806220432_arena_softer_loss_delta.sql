-- 투기장: 지는 쪽 감소폭을 이기는 쪽 상승폭의 85% 로 줄인다.
-- 연패해도 복귀가 덜 막막해진다. 전체 레이팅이 서서히 인플레되는 대신
-- 월요일 부분 초기화(gacha_s2_arena_settle_week)가 이를 되돌린다.
update public.gacha_s2_balance_versions
set config = jsonb_set(config, '{arenaRules,lossDeltaScale}', '0.85'::jsonb)
where active;

-- 승패 판정 RPC 에 패배 보정을 넣는다. 함수가 길어 통째로 다시 쓰지 않고
-- 레이팅 계산 두 줄만 바꾼다.
do $$
declare v_src text;
begin
  v_src := pg_get_functiondef('public.gacha_s2_arena_commit_match(uuid,uuid,boolean,text,text,jsonb,jsonb)'::regprocedure);

  -- 설정값을 읽는 자리를 만든다.
  v_src := replace(
    v_src,
    'v_min_rating := coalesce((v_rules->>''minRating'')::integer, 800);',
    'v_min_rating := coalesce((v_rules->>''minRating'')::integer, 800);'
    || E'\n  v_loss_scale := coalesce((v_rules->>''lossDeltaScale'')::numeric, 1);'
  );
  v_src := replace(
    v_src,
    'v_defender_scale numeric;',
    'v_defender_scale numeric;' || E'\n  v_loss_scale numeric;'
  );

  -- 공격자: 이기면 그대로, 지면 감소폭에 보정을 곱한다.
  v_src := replace(
    v_src,
    '+ round(v_k * ((case when p_attacker_won then 1 else 0 end) - v_attacker_expected))::integer);',
    '+ round(v_k * (case when p_attacker_won then 1 else v_loss_scale end)'
    || ' * ((case when p_attacker_won then 1 else 0 end) - v_attacker_expected))::integer);'
  );
  -- 방어자: 방어자가 진 경우(= 공격자 승리)에 보정을 곱한다.
  v_src := replace(
    v_src,
    '+ round(v_k * v_defender_scale * ((case when p_attacker_won then 0 else 1 end) - v_defender_expected))::integer);',
    '+ round(v_k * v_defender_scale * (case when p_attacker_won then v_loss_scale else 1 end)'
    || ' * ((case when p_attacker_won then 0 else 1 end) - v_defender_expected))::integer);'
  );

  if v_src not like '%v_loss_scale numeric;%' then
    raise exception 'loss scale declaration not applied';
  end if;
  if v_src not like '%lossDeltaScale%' then
    raise exception 'loss scale lookup not applied';
  end if;
  if v_src not like '%then 1 else v_loss_scale end%' then
    raise exception 'attacker loss scale not applied';
  end if;
  if v_src not like '%then v_loss_scale else 1 end%' then
    raise exception 'defender loss scale not applied';
  end if;
  execute v_src;
end;
$$;

do $$
declare
  v_rules jsonb;
begin
  select config->'arenaRules' into v_rules from public.gacha_s2_balance_versions where active;
  if (v_rules->>'lossDeltaScale')::numeric <> 0.85 then
    raise exception 'lossDeltaScale not applied';
  end if;
  -- 기존 투기장 값이 살아 있는지 확인한다.
  if (v_rules->>'eloK')::numeric <> 24
     or (v_rules->>'defenderDeltaScale')::numeric <> 0.8
     or (v_rules->>'minRating')::numeric <> 800 then
    raise exception 'existing arena rules changed';
  end if;
end;
$$;
