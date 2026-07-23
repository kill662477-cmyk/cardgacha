-- Add Vitaming and Haetsal as new SS cards.

begin;

do $$
begin
  if not exists (
    select 1
    from public.gacha_s2_balance_versions
    where version = '2026.07.23-ss-2.9-sss-4.6' and active
  ) then
    raise exception 'active balance version mismatch for Vitaming/Haetsal card addition';
  end if;
end;
$$;

with next_balance as (
  select jsonb_set(
    config,
    '{balanceVersion}',
    to_jsonb('2026.07.23-vitaming-haetsal-ss'::text),
    true
  ) as config
  from public.gacha_s2_balance_versions
  where version = '2026.07.23-ss-2.9-sss-4.6' and active
)
insert into public.gacha_s2_balance_versions (
  version, config_hash, catalog_hash, config, active, activated_at
)
select
  '2026.07.23-vitaming-haetsal-ss',
  '3125414664f6790a9d6268407b83c6f631b26d82abe8757e500d410e04099219',
  '116592cd6727708405e96c810b1610e21b4f90958b8814ce7dd1fc4724b545c3',
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
where version = '2026.07.23-vitaming-haetsal-ss';

insert into public.gacha_s2_card_catalog (
  card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group, balance_version
)
values
  ('vitaming-15', '비타밍', 'vitaming-15.png', 'SS', '테란', 'boss', 'MUR', false, '2026.07.23-vitaming-haetsal-ss'),
  ('haetsal-13', '햇살', 'haetsal-13.jpg', 'SS', '테란', 'quick', 'MUR', false, '2026.07.23-vitaming-haetsal-ss')
on conflict (card_id) do update
set member = excluded.member,
    asset_file = excluded.asset_file,
    rarity = excluded.rarity,
    race = excluded.race,
    archetype = excluded.archetype,
    source_rarity = excluded.source_rarity,
    is_group = excluded.is_group,
    balance_version = excluded.balance_version,
    updated_at = now();

do $$
begin
  if (select count(*) from public.gacha_s2_card_catalog) <> 221 then
    raise exception 'Season 2 catalog must contain exactly 221 cards';
  end if;
  if (select count(*) from public.gacha_s2_card_catalog where rarity = 'SS') <> 25 then
    raise exception 'Season 2 catalog must contain exactly 25 SS cards';
  end if;
  if not exists (
    select 1 from public.gacha_s2_card_catalog
    where card_id = 'vitaming-15'
      and member = '비타밍'
      and asset_file = 'vitaming-15.png'
      and rarity = 'SS'
      and race = '테란'
      and archetype = 'boss'
  ) then
    raise exception 'vitaming-15 catalog validation failed';
  end if;
  if not exists (
    select 1 from public.gacha_s2_card_catalog
    where card_id = 'haetsal-13'
      and member = '햇살'
      and asset_file = 'haetsal-13.jpg'
      and rarity = 'SS'
      and race = '테란'
      and archetype = 'quick'
  ) then
    raise exception 'haetsal-13 catalog validation failed';
  end if;
  if not exists (
    select 1 from public.gacha_s2_balance_versions
    where version = '2026.07.23-vitaming-haetsal-ss'
      and active
      and config_hash = '3125414664f6790a9d6268407b83c6f631b26d82abe8757e500d410e04099219'
      and catalog_hash = '116592cd6727708405e96c810b1610e21b4f90958b8814ce7dd1fc4724b545c3'
  ) then
    raise exception 'Vitaming/Haetsal balance activation failed';
  end if;
end;
$$;

commit;
