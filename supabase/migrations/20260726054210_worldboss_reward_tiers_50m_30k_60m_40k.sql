-- 월드보스 보상 티어 재설정. 앵커 = 개인딜 5,000만 -> 30,000P / 6,000만 -> 40,000P.
--
-- 특성 상향(약화·생존·강타·증폭)으로 화력이 올라 기존 최고 티어(4,000만 = 30,000P)가 쉬워졌다.
-- 실측(최근 2일 1,320명): 평균 개인딜 31.4M, 최대 49.0M.
-- 예상 평균 지급 16,958 -> 15,843 (-6.6%). 상단 목표만 높아지고 일반 구간 체감은 유지된다.
--
-- 사전 확인(과거 사고 재발 방지):
--   gacha_s2_world_boss_players.claimed_tier  between -1 and 15  -> 9티어면 인덱스 최대 8. 안전.
--   gacha_s2_world_boss_players.reward_points between 0 and 100000 -> 최대 40000. 안전.
-- 이 두 제약을 넘겨 보상 수령이 전부 실패한 사고가 2026-07-25 에 두 번 있었다.
-- gacha_s2_claim_world_boss_reward 는 config 의 rewardTiers 를 ordinality 역순으로 훑어
-- 최고 달성 티어를 고른다. 하드코딩된 티어 수는 없다.

-- 1) 제약이 새 티어를 수용하는지 먼저 검증하고, 아니면 여기서 멈춘다.
do $$
declare v_tier_ok boolean; v_points_ok boolean;
begin
  select pg_get_constraintdef(oid) like '%<= 15%' into v_tier_ok
  from pg_constraint where conrelid = 'public.gacha_s2_world_boss_players'::regclass
    and conname = 'gacha_s2_world_boss_players_claimed_tier_check';
  select pg_get_constraintdef(oid) like '%100000%' into v_points_ok
  from pg_constraint where conrelid = 'public.gacha_s2_world_boss_players'::regclass
    and conname = 'gacha_s2_world_boss_players_reward_points_check';
  if not coalesce(v_tier_ok, false) then
    raise exception 'claimed_tier 제약이 9티어(인덱스 8)를 수용하지 못한다';
  end if;
  if not coalesce(v_points_ok, false) then
    raise exception 'reward_points 제약이 40000 을 수용하지 못한다';
  end if;
end;
$$;

update public.gacha_s2_balance_versions
set config = jsonb_set(config, '{worldBossRules,rewardTiers}', $tiers$[
  {"damage":1,"points":1200,"failurePoints":300,"label":"참여"},
  {"damage":2000000,"points":2500,"failurePoints":600,"label":"200만"},
  {"damage":5000000,"points":4500,"failurePoints":1200,"label":"500만"},
  {"damage":10000000,"points":7000,"failurePoints":2000,"label":"1,000만"},
  {"damage":20000000,"points":12000,"failurePoints":4000,"label":"2,000만"},
  {"damage":30000000,"points":18000,"failurePoints":6000,"label":"3,000만"},
  {"damage":40000000,"points":24000,"failurePoints":9000,"label":"4,000만"},
  {"damage":50000000,"points":30000,"failurePoints":12000,"label":"5,000만"},
  {"damage":60000000,"points":40000,"failurePoints":15000,"label":"6,000만"}
]$tiers$::jsonb, false)
where active;

-- 2) 적용 결과를 실제 계산 경로와 동일한 방식으로 재검증한다.
do $$
declare
  v_cfg jsonb; v_count integer; v_max integer; v_prev bigint := -1; v_d bigint;
  v_idx integer; v_pts integer;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  select count(*), max((t->>'points')::integer) into v_count, v_max
  from jsonb_array_elements(v_cfg->'worldBossRules'->'rewardTiers') t;
  if v_count <> 9 then raise exception 'tier count % (expected 9)', v_count; end if;
  if v_max <> 40000 then raise exception 'max points % (expected 40000)', v_max; end if;
  if v_count - 1 > 15 then raise exception 'claimed_tier 상한 초과'; end if;
  if v_max > 100000 then raise exception 'reward_points 상한 초과'; end if;

  -- 딜 기준 오름차순 확인. SQL 이 ordinality 역순으로 최고 티어를 고르므로 순서가 틀리면 오지급된다.
  for v_d in select (t->>'damage')::bigint
    from jsonb_array_elements(v_cfg->'worldBossRules'->'rewardTiers') with ordinality as x(t, o) order by o
  loop
    if v_d <= v_prev then raise exception 'rewardTiers damage 가 오름차순이 아니다 (% 이후 %)', v_prev, v_d; end if;
    v_prev := v_d;
  end loop;

  -- 앵커 확인: 5,000만 -> 30,000 / 6,000만 -> 40,000 (RPC 와 동일한 조회식)
  select (o - 1)::integer, (t->>'points')::integer into v_idx, v_pts
  from jsonb_array_elements(v_cfg->'worldBossRules'->'rewardTiers') with ordinality as x(t, o)
  where (t->>'damage')::bigint <= 50000000 order by o desc limit 1;
  if v_pts <> 30000 then raise exception '5,000만 딜 지급액이 % (expected 30000)', v_pts; end if;

  select (o - 1)::integer, (t->>'points')::integer into v_idx, v_pts
  from jsonb_array_elements(v_cfg->'worldBossRules'->'rewardTiers') with ordinality as x(t, o)
  where (t->>'damage')::bigint <= 60000000 order by o desc limit 1;
  if v_pts <> 40000 then raise exception '6,000만 딜 지급액이 % (expected 40000)', v_pts; end if;
  if v_idx > 15 then raise exception '최고 티어 인덱스 % 가 제약을 넘는다', v_idx; end if;
end;
$$;;
