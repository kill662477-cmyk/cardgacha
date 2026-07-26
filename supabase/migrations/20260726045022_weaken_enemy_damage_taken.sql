-- 약화 개편: 적 공격력 -15% + 적이 받는 피해 +10%.
-- 이 게임 스테이지에는 적 방어력 스탯이 없어(enemyHp / enemyAttack 뿐)
-- '적 방어력 감소'를 받는 피해 증가로 구현했다. 둘 다 중첩되지 않는다.
update public.gacha_s2_balance_versions
set config = jsonb_set(
  jsonb_set(config, '{archetypes,weaken,weaken}', '0.15'::jsonb, false),
  '{archetypes,weaken,weakenDamage}', '0.10'::jsonb, true)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'archetypes'->'weaken'->>'weaken')::numeric <> 0.15
    or (v_cfg->'archetypes'->'weaken'->>'weakenDamage')::numeric <> 0.10 then
    raise exception 'weaken rework failed';
  end if;
  if (v_cfg->'archetypes'->'sustain'->>'atk')::numeric <> 1.06
    or (v_cfg->'archetypes'->'heavy'->>'crit')::numeric <> 0.12 then
    raise exception 'unexpected archetype drift';
  end if;
end;
$$;;
