-- 약화 특성 감소폭 8% -> 15%.
--
-- 배경: 약화는 적 공격력을 줄이는 디버프인데, 실제 전투 코드가 설정값을 읽지 않고
-- 0.92 를 하드코딩하고 있었다. 그래서 archetypes.weaken.weaken(0.08)은 전투력 점수
-- 계산에만 쓰이고 전투에는 반영되지 않았다. 코드를 설정값 기반으로 바꾸면서 값도 올린다.
--
-- 측정(전 스테이지 x S+5/SS+7/SSS+9 x 시드 20, 5장 중 약화 장수별 승률):
--   8%  -> 0장 62.67% / 1장 63.00% / 5장 61.33%
--   15% -> 0장 62.67% / 1장 64.00% / 5장 61.33%
-- 1장 넣었을 때 이득이 +0.33%p 에서 +1.33%p 로 커진다.
--
-- 중첩은 여전히 되지 않는다(가장 강한 값 하나만 적용, 지속시간만 갱신).
-- 약화 카드는 공격력 0.92 페널티가 장수만큼 쌓이므로 2장 이상은 여전히 손해다.
-- "1장 넣는 서포트"라는 역할을 유지하려는 의도된 설계다.
--
-- 전투 판정은 SQL 이 아니라 JS(엣지 공유 모듈)에서 돈다. 이 설정은 밸런스 정본을
-- 클라이언트와 일치시키기 위한 것이고, 실제 적용은 src/renewal/config.js + 엣지 배포다.

update public.gacha_s2_balance_versions
set config = jsonb_set(config, '{archetypes,weaken,weaken}', '0.15'::jsonb, false)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'archetypes'->'weaken'->>'weaken')::numeric <> 0.15 then
    raise exception 'weaken archetype update failed';
  end if;
  -- 다른 특성 값이 함께 흔들리지 않았는지 확인한다.
  if (v_cfg->'archetypes'->'weaken'->>'atk')::numeric <> 0.92
    or (v_cfg->'archetypes'->'sustain'->>'recovery')::numeric <> 0.08 then
    raise exception 'unexpected archetype drift';
  end if;
end;
$$;
