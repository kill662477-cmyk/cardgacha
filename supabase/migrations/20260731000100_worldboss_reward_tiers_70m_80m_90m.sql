-- 월드보스 개인딜 보상 티어 확장: 7,000만 5만P / 8,000만 6만P / 9,000만 7만P.
-- 실패 시 보상은 기존 기울기(10M 당 +3,000)를 이어 18,000 / 21,000 / 24,000.
--
-- 이 영역은 과거 두 번 사고가 났다. gacha_s2_world_boss_players 의 CHECK 두 개를 반드시 지켜야 한다.
--   claimed_tier  <= 15     -> 티어 12개(최대 인덱스 11) 이므로 통과
--   reward_points <= 100000 -> 최고 70,000 이므로 통과
-- damage 는 반드시 오름차순이어야 한다. SQL 이 ordinality 역순으로 최고 티어를 찾기 때문이다.
update public.gacha_s2_balance_versions
set config = jsonb_set(config, '{worldBossRules,rewardTiers}',
  (config->'worldBossRules'->'rewardTiers') || jsonb_build_array(
    jsonb_build_object('damage', 70000000, 'points', 50000, 'failurePoints', 18000, 'label', '7,000만'),
    jsonb_build_object('damage', 80000000, 'points', 60000, 'failurePoints', 21000, 'label', '8,000만'),
    jsonb_build_object('damage', 90000000, 'points', 70000, 'failurePoints', 24000, 'label', '9,000만')
  ))
where active;

do $$
declare
  v_tiers jsonb;
  v_count integer;
  v_max_points integer;
  v_prev bigint := -1;
  v_row jsonb;
begin
  select config->'worldBossRules'->'rewardTiers' into v_tiers
  from public.gacha_s2_balance_versions where active;

  v_count := jsonb_array_length(v_tiers);
  if v_count <> 12 then
    raise exception 'reward tier count mismatch: %', v_count;
  end if;
  if v_count - 1 > 15 then
    raise exception 'claimed_tier upper bound (15) exceeded: %', v_count - 1;
  end if;

  select max((t->>'points')::integer) into v_max_points from jsonb_array_elements(v_tiers) t;
  if v_max_points > 100000 then
    raise exception 'reward_points upper bound (100000) exceeded: %', v_max_points;
  end if;

  for v_row in select value from jsonb_array_elements(v_tiers) loop
    if (v_row->>'damage')::bigint <= v_prev then
      raise exception 'reward tier damage not ascending at %', v_row->>'damage';
    end if;
    v_prev := (v_row->>'damage')::bigint;
  end loop;
end;
$$;
