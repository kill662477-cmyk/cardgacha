update public.gacha_s2_balance_versions
set config = jsonb_set(
  jsonb_set(
  jsonb_set(
    config,
    '{archetypes,sustain,atk}', '1.06'::jsonb, false),
    '{archetypes,heavy,atk}', '1.31'::jsonb, false),
    '{archetypes,heavy,crit}', '0.12'::jsonb, true)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'archetypes'->'sustain'->>'atk')::numeric <> 1.06
    or (v_cfg->'archetypes'->'heavy'->>'atk')::numeric <> 1.31
    or (v_cfg->'archetypes'->'heavy'->>'crit')::numeric <> 0.12 then
    raise exception 'archetype retune failed';
  end if;
  -- 손대지 않은 값이 함께 흔들리지 않았는지 확인한다.
  if (v_cfg->'archetypes'->'sustain'->>'hp')::numeric <> 1.24
    or (v_cfg->'archetypes'->'sustain'->>'recovery')::numeric <> 0.08
    or (v_cfg->'archetypes'->'heavy'->>'speed')::numeric <> 0.78
    or (v_cfg->'archetypes'->'weaken'->>'weaken')::numeric <> 0.15 then
    raise exception 'unexpected archetype drift';
  end if;
end;
$$;;
