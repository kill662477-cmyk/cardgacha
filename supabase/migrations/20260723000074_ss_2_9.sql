-- Raise the SS rarity multiplier from 2.7 to 2.9 while retaining SSS at 4.6.

begin;

with next_balance as (
  select
    catalog_hash,
    jsonb_set(
      jsonb_set(
        config,
        '{balanceVersion}',
        to_jsonb('2026.07.23-ss-2.9-sss-4.6'::text),
        true
      ),
      '{rarities,SS,multiplier}',
      '2.9'::jsonb,
      true
    ) as config
  from public.gacha_s2_balance_versions
  where active
)
insert into public.gacha_s2_balance_versions (
  version, config_hash, catalog_hash, config, active, activated_at
)
select
  '2026.07.23-ss-2.9-sss-4.6',
  '5212b45d587374906869d7996c1a3fff13ad5f51436d9d3d6b187fb141533d8b',
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

update public.gacha_s2_balance_versions set active = false where active;
update public.gacha_s2_balance_versions
set active = true, activated_at = now()
where version = '2026.07.23-ss-2.9-sss-4.6';

do $$
declare
  v_ss_multiplier numeric;
  v_sss_multiplier numeric;
begin
  select
    (config->'rarities'->'SS'->>'multiplier')::numeric,
    (config->'rarities'->'SSS'->>'multiplier')::numeric
  into v_ss_multiplier, v_sss_multiplier
  from public.gacha_s2_balance_versions
  where version = '2026.07.23-ss-2.9-sss-4.6' and active;

  if v_ss_multiplier <> 2.9 or v_sss_multiplier <> 4.6 then
    raise exception 'SS/SSS multiplier activation failed';
  end if;
end;
$$;

commit;
