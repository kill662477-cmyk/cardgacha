-- Add four requested high-rarity cards.

begin;

do $$
begin
  if (select count(*) from public.gacha_s2_balance_versions where active) <> 1 then
    raise exception 'exactly one active balance version is required';
  end if;
end;
$$;

with active_balance as (
  select version
  from public.gacha_s2_balance_versions
  where active
),
new_cards (
  card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group
) as (
  values
    ('parksubeom-6', '박수범', 'parksubeom-6.jpg', 'SSS', '프로토스', 'boss', 'FUR', false),
    ('vitaming-16', '비타밍', 'vitaming-16.png', 'SS', '테란', 'amplify', 'MUR', false),
    ('jidongwon-8', '지동원', 'jidongwon-8.jpg', 'SSS', '테란', 'amplify', 'FUR', false),
    ('arisongi-12', '아리송이', 'arisongi-12.jpg', 'SS', '프로토스', 'boss', 'MUR', false)
)
insert into public.gacha_s2_card_catalog (
  card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group, balance_version
)
select
  new_cards.card_id,
  new_cards.member,
  new_cards.asset_file,
  new_cards.rarity,
  new_cards.race,
  new_cards.archetype,
  new_cards.source_rarity,
  new_cards.is_group,
  active_balance.version
from new_cards
cross join active_balance
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
set catalog_hash = '051d225d343661ce1bea13d2787880edb13acb236aca2ad48008c37fbf57c5c3'
where active;

do $$
begin
  if (select count(*) from public.gacha_s2_card_catalog) <> 228 then
    raise exception 'Season 2 catalog must contain exactly 228 cards';
  end if;
  if (select count(*) from public.gacha_s2_card_catalog where rarity = 'SS') <> 27 then
    raise exception 'Season 2 catalog must contain exactly 27 SS cards';
  end if;
  if (select count(*) from public.gacha_s2_card_catalog where rarity = 'SSS') <> 21 then
    raise exception 'Season 2 catalog must contain exactly 21 SSS cards';
  end if;
  if (
    select count(*)
    from public.gacha_s2_card_catalog
    where (card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group) in (
      ('parksubeom-6', '박수범', 'parksubeom-6.jpg', 'SSS', '프로토스', 'boss', 'FUR', false),
      ('vitaming-16', '비타밍', 'vitaming-16.png', 'SS', '테란', 'amplify', 'MUR', false),
      ('jidongwon-8', '지동원', 'jidongwon-8.jpg', 'SSS', '테란', 'amplify', 'FUR', false),
      ('arisongi-12', '아리송이', 'arisongi-12.jpg', 'SS', '프로토스', 'boss', 'MUR', false)
    )
  ) <> 4 then
    raise exception 'requested card catalog validation failed';
  end if;
  if not exists (
    select 1
    from public.gacha_s2_balance_versions
    where active
      and catalog_hash = '051d225d343661ce1bea13d2787880edb13acb236aca2ad48008c37fbf57c5c3'
  ) then
    raise exception 'active catalog hash update failed';
  end if;
end;
$$;

commit;
