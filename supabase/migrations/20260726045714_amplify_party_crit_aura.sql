-- 증폭 개편: 자기 치명타(+9%p) + 파티 딜 배수(+4%, 중첩) -> 파티 전체 치명타 오라(+15%p, 중첩).
-- 강타에 치명타 확률을 준 뒤 역할이 겹쳤고, 기존 구조는 5장을 다 넣어도 승률 이득이
-- +0.66%p 뿐이라 사실상 죽은 특성이었다.
-- 치명타 총합 상한 60%는 코드(computeCardStats)에 있다. 2~3장에서 정점을 찍는 구조다.
update public.gacha_s2_balance_versions
set config = jsonb_set(
  config #- '{archetypes,amplify,amplify}' #- '{archetypes,amplify,crit}',
  '{archetypes,amplify,critAura}', '0.15'::jsonb, true)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'archetypes'->'amplify'->>'critAura')::numeric <> 0.15 then
    raise exception 'amplify crit aura not applied';
  end if;
  if v_cfg->'archetypes'->'amplify' ? 'amplify' or v_cfg->'archetypes'->'amplify' ? 'crit' then
    raise exception 'old amplify keys still present';
  end if;
  if (v_cfg->'archetypes'->'weaken'->>'weakenDamage')::numeric <> 0.10
    or (v_cfg->'archetypes'->'heavy'->>'crit')::numeric <> 0.12
    or (v_cfg->'archetypes'->'sustain'->>'atk')::numeric <> 1.06 then
    raise exception 'unexpected archetype drift';
  end if;
end;
$$;;
