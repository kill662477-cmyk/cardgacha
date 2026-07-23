-- Retune the top rarity multipliers: SS 2.7, SSS 4.8.

begin;

with next_balance as (
  select
    catalog_hash,
    jsonb_set(
      jsonb_set(
        jsonb_set(
          config,
          '{balanceVersion}',
          to_jsonb('2026.07.23-ss-2.7-sss-4.8'::text),
          true
        ),
        '{rarities,SS,multiplier}',
        '2.7'::jsonb,
        true
      ),
      '{rarities,SSS,multiplier}',
      '4.8'::jsonb,
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
  '2026.07.23-ss-2.7-sss-4.8',
  '41ddcc3a8875d39e0e6a3c3134812b1e063ddef41b8e470dab82cee950f1dd24',
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
where version = '2026.07.23-ss-2.7-sss-4.8';

do $$
declare
  v_ss_multiplier numeric;
  v_sss_multiplier numeric;
  v_s_multiplier numeric;
  v_plus_three numeric;
  v_plus_nine numeric;
begin
  select
    (config->'rarities'->'SS'->>'multiplier')::numeric,
    (config->'rarities'->'SSS'->>'multiplier')::numeric,
    (config->'rarities'->'S'->>'multiplier')::numeric,
    (config->'enhancement'->'statMultipliers'->>3)::numeric,
    (config->'enhancement'->'statMultipliers'->>9)::numeric
  into v_ss_multiplier, v_sss_multiplier, v_s_multiplier, v_plus_three, v_plus_nine
  from public.gacha_s2_balance_versions
  where version = '2026.07.23-ss-2.7-sss-4.8'
    and active;

  if v_ss_multiplier <> 2.7 or v_sss_multiplier <> 4.8 then
    raise exception 'SS/SSS multiplier activation failed';
  end if;

  if v_sss_multiplier * v_plus_three <= v_s_multiplier * v_plus_nine then
    raise exception 'SSS +3 must exceed S +9';
  end if;
end;
$$;

commit;
