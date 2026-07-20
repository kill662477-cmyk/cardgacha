-- Card Gacha Season 2: add jjiking-13 (찌킹, SS) + swap jjiking-5's photo.
--
-- Expands the fixed roster from 213 -> 214 cards (SS 22 -> 23). jjiking-5 keeps
-- its id/rarity/archetype (C, quick) -- only its asset_file changes (png -> jpg).
-- Scoped insert/update + catalog_hash refresh instead of re-running the full
-- migration 002 seed. config_hash is unchanged (card list only, hashed
-- separately as catalog_hash).

insert into public.gacha_s2_card_catalog (
  card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group, balance_version
) values (
  'jjiking-13', '찌킹', 'jjiking-13.jpg', 'SS', '저그', 'area', 'MUR', false, '2026.07.18-random-loot-1'
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

update public.gacha_s2_card_catalog
set asset_file = 'jjiking-5.jpg', updated_at = now()
where card_id = 'jjiking-5';

update public.gacha_s2_balance_versions
set catalog_hash = '8e7351c09b8fe082cb9d54e1884e5c409a664230b291ec7a1e18fb3d16555014'
where version = '2026.07.18-random-loot-1' and active;

do $$
declare
  v_total integer;
  v_ss integer;
  v_catalog_hash text;
  v_jjiking5_file text;
begin
  select count(*) into v_total from public.gacha_s2_card_catalog;
  if v_total <> 214 then raise exception 'Season 2 catalog must contain exactly 214 cards, found %', v_total; end if;
  select count(*) into v_ss from public.gacha_s2_card_catalog where rarity = 'SS';
  if v_ss <> 23 then raise exception 'SS rarity must contain exactly 23 cards, found %', v_ss; end if;
  if exists (
    select 1 from public.gacha_s2_card_catalog
    where rarity <> 'EX'
    group by rarity
    having count(distinct archetype) <> 8
  ) then
    raise exception 'every combat rarity must contain all 8 archetypes';
  end if;
  select asset_file into v_jjiking5_file from public.gacha_s2_card_catalog where card_id = 'jjiking-5';
  if v_jjiking5_file is distinct from 'jjiking-5.jpg' then raise exception 'jjiking-5 asset_file swap failed'; end if;
  select catalog_hash into v_catalog_hash
  from public.gacha_s2_balance_versions
  where version = '2026.07.18-random-loot-1' and active;
  if v_catalog_hash is distinct from '8e7351c09b8fe082cb9d54e1884e5c409a664230b291ec7a1e18fb3d16555014' then
    raise exception 'catalog hash mismatch';
  end if;
end;
$$;
