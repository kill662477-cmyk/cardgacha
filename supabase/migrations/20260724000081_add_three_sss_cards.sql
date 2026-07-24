-- Add Byeon Hyeon-je, Sate, and Arisongi as new SSS cards.

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
    ('byeonhyeonje-7', '변현제', 'byeonhyeonje-7.jpg', 'SSS', '프로토스', 'quick', 'FUR', false),
    ('sate-5', '사테', 'sate-5.png', 'SSS', '테란', 'heavy', 'FUR', false),
    ('arisongi-11', '아리송이', 'arisongi-11.png', 'SSS', '프로토스', 'area', 'FUR', false)
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
set catalog_hash = 'c0afef0b434bfd6b91648f74e7555e098b1327562a51c917b8cd4f1e7a71df11'
where active;
do $$
begin
  if (select count(*) from public.gacha_s2_card_catalog) <> 224 then
    raise exception 'Season 2 catalog must contain exactly 224 cards';
  end if;
  if (select count(*) from public.gacha_s2_card_catalog where rarity = 'SSS') <> 19 then
    raise exception 'Season 2 catalog must contain exactly 19 SSS cards';
  end if;
  if (
    select count(*)
    from public.gacha_s2_card_catalog
    where (card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group) in (
      ('byeonhyeonje-7', '변현제', 'byeonhyeonje-7.jpg', 'SSS', '프로토스', 'quick', 'FUR', false),
      ('sate-5', '사테', 'sate-5.png', 'SSS', '테란', 'heavy', 'FUR', false),
      ('arisongi-11', '아리송이', 'arisongi-11.png', 'SSS', '프로토스', 'area', 'FUR', false)
    )
  ) <> 3 then
    raise exception 'new SSS card catalog validation failed';
  end if;
  if not exists (
    select 1
    from public.gacha_s2_balance_versions
    where active
      and catalog_hash = 'c0afef0b434bfd6b91648f74e7555e098b1327562a51c917b8cd4f1e7a71df11'
  ) then
    raise exception 'active catalog hash update failed';
  end if;
end;
$$;
commit;
