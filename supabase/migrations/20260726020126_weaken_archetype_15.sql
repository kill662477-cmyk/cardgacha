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
  if (v_cfg->'archetypes'->'weaken'->>'atk')::numeric <> 0.92
    or (v_cfg->'archetypes'->'sustain'->>'recovery')::numeric <> 0.08 then
    raise exception 'unexpected archetype drift';
  end if;
end;
$$;;
