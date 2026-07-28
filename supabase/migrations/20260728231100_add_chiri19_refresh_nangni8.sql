-- Refresh the existing 낭니 SSS artwork and add 치리 SS as a new card.

begin;

do $$
begin
  if (select count(*) from public.gacha_s2_balance_versions where active) <> 1 then
    raise exception 'exactly one active balance version is required';
  end if;
end;
$$;

update public.gacha_s2_card_catalog
set asset_file = 'nangni-8-r1.jpg',
    updated_at = now()
where card_id = 'nangni-8'
  and member = '낭니'
  and rarity = 'SSS';

do $$
begin
  if not exists (
    select 1
    from public.gacha_s2_card_catalog
    where card_id = 'nangni-8'
      and member = '낭니'
      and asset_file = 'nangni-8-r1.jpg'
      and rarity = 'SSS'
  ) then
    raise exception 'nangni-8 SSS card was not found';
  end if;
end;
$$;

with active_balance as (
  select version
  from public.gacha_s2_balance_versions
  where active
)
insert into public.gacha_s2_card_catalog (
  card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group, balance_version
)
select
  'chiri-19',
  '치리',
  'chiri-19.jpg',
  'SS',
  '저그',
  'heavy',
  'MUR',
  false,
  active_balance.version
from active_balance
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

update public.gacha_s2_balance_versions
set catalog_hash = 'f808d95c44b60d869b0b94ed2d509fb127e91aa7a3880737bada8916b4e368c8'
where active;

do $$
begin
  if (select count(*) from public.gacha_s2_card_catalog) <> 229 then
    raise exception 'Season 2 catalog must contain exactly 229 cards';
  end if;
  if (select count(*) from public.gacha_s2_card_catalog where rarity = 'SS') <> 28 then
    raise exception 'Season 2 catalog must contain exactly 28 SS cards';
  end if;
  if (select count(*) from public.gacha_s2_card_catalog where rarity = 'SSS') <> 21 then
    raise exception 'Season 2 catalog must contain exactly 21 SSS cards';
  end if;
  if not exists (
    select 1
    from public.gacha_s2_card_catalog
    where card_id = 'nangni-8'
      and member = '낭니'
      and asset_file = 'nangni-8-r1.jpg'
      and rarity = 'SSS'
      and race = '저그'
      and archetype = 'boss'
  ) then
    raise exception 'nangni-8 artwork refresh validation failed';
  end if;
  if not exists (
    select 1
    from public.gacha_s2_card_catalog
    where card_id = 'chiri-19'
      and member = '치리'
      and asset_file = 'chiri-19.jpg'
      and rarity = 'SS'
      and race = '저그'
      and archetype = 'heavy'
      and source_rarity = 'MUR'
      and not is_group
  ) then
    raise exception 'chiri-19 catalog validation failed';
  end if;
  if not exists (
    select 1
    from public.gacha_s2_balance_versions
    where active
      and catalog_hash = 'f808d95c44b60d869b0b94ed2d509fb127e91aa7a3880737bada8916b4e368c8'
  ) then
    raise exception 'active catalog hash update failed';
  end if;
end;
$$;

commit;
