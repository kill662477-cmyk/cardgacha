update public.gacha_s2_balance_versions
set config = jsonb_set(config, '{archetypes,weaken,weaken}', '0.20'::jsonb, false)
where active;

do $$
declare v_cfg jsonb;
begin
  select config into v_cfg from public.gacha_s2_balance_versions where active;
  if (v_cfg->'archetypes'->'weaken'->>'weaken')::numeric <> 0.20 then
    raise exception 'weaken 20 update failed';
  end if;
  if (v_cfg->'archetypes'->'sustain'->>'atk')::numeric <> 1.06
    or (v_cfg->'archetypes'->'heavy'->>'crit')::numeric <> 0.12 then
    raise exception 'unexpected archetype drift';
  end if;
end;
$$;;
