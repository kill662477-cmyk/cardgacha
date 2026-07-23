-- Raise the SSS rarity multiplier so SSS +3 exceeds S +9 at equal conditions.

begin;

with next_balance as (
  select
    catalog_hash,
    jsonb_set(
      jsonb_set(
        config,
        '{balanceVersion}',
        to_jsonb('2026.07.23-sss-multiplier-5'::text),
        true
      ),
      '{rarities,SSS,multiplier}',
      '5'::jsonb,
      true
    ) as config
  from public.gacha_s2_balance_versions
  where active
)
insert into public.gacha_s2_balance_versions (
  version,
  config_hash,
  catalog_hash,
  config,
  active,
  activated_at
)
select
  '2026.07.23-sss-multiplier-5',
  '9b19b57c44adaa67d3f3ce094fa62555fbba04513960d21dd12ea9ffe8a9f082',
  catalog_hash,
  config,
  false,
  now()
from next_balance
on conflict (version) do update
set config_hash = excluded.config_hash,
    catalog_hash = excluded.catalog_hash,
    config = excluded.config,
    activated_at = excluded.activated_at;

update public.gacha_s2_balance_versions
set active = false
where active;

update public.gacha_s2_balance_versions
set active = true,
    activated_at = now()
where version = '2026.07.23-sss-multiplier-5';

do $$
declare
  v_sss_multiplier numeric;
  v_s_multiplier numeric;
  v_plus_three numeric;
  v_plus_nine numeric;
begin
  select
    (config->'rarities'->'SSS'->>'multiplier')::numeric,
    (config->'rarities'->'S'->>'multiplier')::numeric,
    (config->'enhancement'->'statMultipliers'->>3)::numeric,
    (config->'enhancement'->'statMultipliers'->>9)::numeric
  into v_sss_multiplier, v_s_multiplier, v_plus_three, v_plus_nine
  from public.gacha_s2_balance_versions
  where version = '2026.07.23-sss-multiplier-5'
    and active;

  if v_sss_multiplier <> 5 then
    raise exception 'SSS multiplier activation failed';
  end if;

  if v_sss_multiplier * v_plus_three <= v_s_multiplier * v_plus_nine then
    raise exception 'SSS +3 must exceed S +9';
  end if;
end;
$$;

commit;
