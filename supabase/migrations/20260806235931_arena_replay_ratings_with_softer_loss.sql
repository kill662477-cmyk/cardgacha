-- 패배 감소폭 85% 보정을 소급 적용한다.
-- 보정 전에 치른 판들은 옛 공식으로 계산돼 있어, 지금부터만 적용하면 일찍 시작한
-- 사람이 손해를 본다. 초기화 이후 4,493 판을 처음부터 순서대로 다시 계산한다.
--
-- 드라이런 결과: 406 명 중 내려가는 사람 0 명, 평균 +15, 최대 +37.
-- 등수는 372 명이 바뀌지만 상위 3 등은 그대로다. 주간 정산은 아직 한 번도 돌지
-- 않았으므로(gacha_s2_arena_weekly_rewards 비어 있음) 지급된 보상에는 영향이 없다.

-- 되돌릴 수 있게 현재 값을 남긴다.
create table if not exists public.gacha_s2_arena_players_backup_20260806 as
select *, now() as backed_up_at from public.gacha_s2_arena_players;

create table if not exists public.gacha_s2_arena_matches_backup_20260806 as
select match_id, attacker_rating_before, attacker_rating_after,
       defender_rating_before, defender_rating_after, now() as backed_up_at
from public.gacha_s2_arena_matches;

do $$
declare
  v_rules jsonb;
  v_k numeric; v_ds numeric; v_ls numeric;
  v_min integer; v_start integer;
  m record;
  a_before integer; d_before integer; a_after integer; d_after integer;
  a_exp numeric; d_exp numeric;
  v_count integer := 0;
begin
  select config->'arenaRules' into v_rules from public.gacha_s2_balance_versions where active;
  v_k     := coalesce((v_rules->>'eloK')::numeric, 24);
  v_ds    := coalesce((v_rules->>'defenderDeltaScale')::numeric, 0.8);
  v_ls    := coalesce((v_rules->>'lossDeltaScale')::numeric, 1);
  v_min   := coalesce((v_rules->>'minRating')::integer, 800);
  v_start := coalesce((v_rules->>'startRating')::integer, 1000);

  if v_ls <> 0.85 then
    raise exception 'lossDeltaScale 가 0.85 가 아니다: %', v_ls;
  end if;

  create temp table replay_rating (
    user_id uuid primary key, rating integer, peak integer
  ) on commit drop;

  -- 매치를 시간순으로 재생한다. 저장된 *_rating_before 는 옛 공식으로 계산된 값이라
  -- 쓰면 안 된다. 매 판마다 그 시점의 누적 레이팅을 새로 계산해서 쓴다.
  for m in
    select match_id, attacker_id, defender_id, attacker_won
    from public.gacha_s2_arena_matches
    where status = 'resolved' and attacker_won is not null
    order by resolved_at, match_id
  loop
    insert into replay_rating values (m.attacker_id, v_start, v_start) on conflict do nothing;
    insert into replay_rating values (m.defender_id, v_start, v_start) on conflict do nothing;
    select rating into a_before from replay_rating where user_id = m.attacker_id;
    select rating into d_before from replay_rating where user_id = m.defender_id;

    a_exp := 1 / (1 + power(10, (d_before - a_before)::numeric / 400));
    d_exp := 1 / (1 + power(10, (a_before - d_before)::numeric / 400));

    a_after := greatest(v_min, a_before + round(v_k
      * (case when m.attacker_won then 1 else v_ls end)
      * ((case when m.attacker_won then 1 else 0 end) - a_exp))::integer);
    d_after := greatest(v_min, d_before + round(v_k * v_ds
      * (case when m.attacker_won then v_ls else 1 end)
      * ((case when m.attacker_won then 0 else 1 end) - d_exp))::integer);

    -- 최근 전적 화면이 현재 레이팅과 맞아떨어지도록 매치 기록도 같이 고친다.
    update public.gacha_s2_arena_matches
    set attacker_rating_before = a_before, attacker_rating_after = a_after,
        defender_rating_before = d_before, defender_rating_after = d_after
    where match_id = m.match_id;

    update replay_rating set rating = a_after, peak = greatest(peak, a_after) where user_id = m.attacker_id;
    update replay_rating set rating = d_after, peak = greatest(peak, d_after) where user_id = m.defender_id;
    v_count := v_count + 1;
  end loop;

  update public.gacha_s2_arena_players p
  set rating = r.rating, peak_rating = r.peak, updated_at = now()
  from replay_rating r
  where p.user_id = r.user_id;

  raise notice 'replayed % matches', v_count;
end;
$$;

do $$
declare
  v_down integer;
  v_mismatch integer;
begin
  -- 아무도 손해를 보면 안 된다. 감소폭만 줄인 보정이라 내려가는 사람이 나오면 계산이 틀린 것이다.
  select count(*) into v_down
  from public.gacha_s2_arena_players p
  join public.gacha_s2_arena_players_backup_20260806 b using (user_id)
  where p.rating < b.rating;
  if v_down > 0 then
    raise exception '% players lost rating - replay is wrong', v_down;
  end if;

  -- 각자의 마지막 판 결과가 현재 레이팅과 맞아야 한다.
  select count(*) into v_mismatch from (
    select distinct on (user_id) user_id, final from (
      select attacker_id as user_id, attacker_rating_after as final, resolved_at, match_id
      from public.gacha_s2_arena_matches where status = 'resolved'
      union all
      select defender_id, defender_rating_after, resolved_at, match_id
      from public.gacha_s2_arena_matches where status = 'resolved'
    ) all_sides order by user_id, resolved_at desc, match_id desc
  ) last_side
  join public.gacha_s2_arena_players p using (user_id)
  where p.rating <> last_side.final;
  if v_mismatch > 0 then
    raise exception '% players do not match their last recorded match', v_mismatch;
  end if;

  if exists (select 1 from public.gacha_s2_arena_players where rating < 800) then
    raise exception 'rating fell below the floor';
  end if;
end;
$$;
