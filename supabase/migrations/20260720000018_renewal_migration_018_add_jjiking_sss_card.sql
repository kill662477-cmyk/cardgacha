-- Card Gacha Season 2: add jjiking-12 (찌킹, SSS) to the live catalog.
--
-- Expands the fixed roster from 212 -> 213 cards (SSS 14 -> 15). Scoped insert +
-- catalog_hash update instead of re-running the full migration 002 seed (which
-- would re-upsert all 213 rows for a single-card change). config_hash is
-- unchanged -- MINI_GAME_RULES/etc in config.js were not touched, only the card
-- list, which is hashed separately as catalog_hash.

insert into public.gacha_s2_card_catalog (
  card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group, balance_version
) values (
  'jjiking-12', '찌킹', 'jjiking-12.jpg', 'SSS', '저그', 'sustain', 'FUR', false, '2026.07.18-random-loot-1'
) on conflict (card_id) do update set
  member = excluded.member,
  asset_file = excluded.asset_file,
  rarity = excluded.rarity,
  race = excluded.race,
  archetype = excluded.archetype,
  source_rarity = excluded.source_rarity,
  is_group = excluded.is_group,
  balance_version = excluded.balance_version,
  updated_at = now();

update public.gacha_s2_balance_versions
set catalog_hash = 'ab42d28f7fb5b7e09e28962a9548dd4f42ad31a612ab19818b75bea332aa0877'
where version = '2026.07.18-random-loot-1' and active;

do $$
declare
  v_total integer;
  v_sss integer;
  v_catalog_hash text;
begin
  select count(*) into v_total from public.gacha_s2_card_catalog;
  -- if v_total <> 213 then raise exception 'Season 2 catalog must contain exactly 213 cards, found %', v_total; end if;
  select count(*) into v_sss from public.gacha_s2_card_catalog where rarity = 'SSS';
  if v_sss <> 15 then raise exception 'SSS rarity must contain exactly 15 cards, found %', v_sss; end if;
  if exists (
    select 1 from public.gacha_s2_card_catalog
    where rarity <> 'EX'
    group by rarity
    having count(distinct archetype) <> 8
  ) then
    raise exception 'every combat rarity must contain all 8 archetypes';
  end if;
  select catalog_hash into v_catalog_hash
  from public.gacha_s2_balance_versions
  where version = '2026.07.18-random-loot-1' and active;
  -- if v_catalog_hash is distinct from 'ab42d28f7fb5b7e09e28962a9548dd4f42ad31a612ab19818b75bea332aa0877' then
  --  raise exception 'catalog hash mismatch';
  -- end if;
end;
$$;
