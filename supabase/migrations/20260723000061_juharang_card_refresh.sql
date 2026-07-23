-- Replace all Juharang card art, add five cards, and apply the requested rarity layout.
begin;

do $$
begin
  if not exists (
    select 1 from public.gacha_s2_balance_versions
    where version = '2026.07.22-worldboss-escalation-1' and active
  ) then
    raise exception 'active balance version mismatch for Juharang refresh';
  end if;
end;
$$;

update public.gacha_s2_balance_versions
set catalog_hash = 'cea594b3d22a2a643b9a81fbf0f6558f8d693528632c4cefe085891f34093928'
where version = '2026.07.22-worldboss-escalation-1';

insert into public.gacha_s2_card_catalog (
  card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group, balance_version
)
values
  ('juharang-1', '주하랑', 'juharang-1.webp', 'C', '프로토스', 'boss', 'R', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-2', '주하랑', 'juharang-2.webp', 'SSS', '프로토스', 'weaken', 'FUR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-3', '주하랑', 'juharang-3.webp', 'SS', '프로토스', 'quick', 'MUR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-4', '주하랑', 'juharang-4.webp', 'SS', '프로토스', 'heavy', 'MUR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-5', '주하랑', 'juharang-5.webp', 'D', '프로토스', 'sustain', 'RRR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-6', '주하랑', 'juharang-6.webp', 'S', '프로토스', 'boss', 'UR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-7', '주하랑', 'juharang-7.webp', 'A', '프로토스', 'quick', 'SAR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-8', '주하랑', 'juharang-8.webp', 'C', '프로토스', 'weaken', 'R', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-9', '주하랑', 'juharang-9.webp', 'B', '프로토스', 'quick', 'SR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-10', '주하랑', 'juharang-10.webp', 'F', '프로토스', 'boss', 'U', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-11', '주하랑', 'juharang-11.webp', 'F', '프로토스', 'quick', 'U', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-12', '주하랑', 'juharang-12.webp', 'E', '프로토스', 'quick', 'RR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-13', '주하랑', 'juharang-13.webp', 'E', '프로토스', 'heavy', 'RR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-14', '주하랑', 'juharang-14.webp', 'D', '프로토스', 'quick', 'RRR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-16', '주하랑', 'juharang-16.webp', 'A', '프로토스', 'heavy', 'SAR', false, '2026.07.22-worldboss-escalation-1'),
  ('juharang-17', '주하랑', 'juharang-17.webp', 'S', '프로토스', 'quick', 'UR', false, '2026.07.22-worldboss-escalation-1')
on conflict (card_id) do update set
  member = excluded.member,
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
  if (select count(*) from public.gacha_s2_card_catalog) <> 219 then
    raise exception 'Season 2 catalog must contain exactly 219 cards';
  end if;
  if (select count(*) from public.gacha_s2_card_catalog where member = '주하랑') <> 16 then
    raise exception 'Juharang catalog must contain exactly 16 cards';
  end if;
  if exists (select 1 from public.gacha_s2_card_catalog where card_id = 'juharang-15') then
    raise exception 'juharang-15 must remain excluded';
  end if;
  if (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-2') <> 'SSS'
    or (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-3') <> 'SS'
    or (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-4') <> 'SS'
    or (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-6') <> 'S'
    or (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-17') <> 'S' then
    raise exception 'Juharang fixed rarity validation failed';
  end if;
end;
$$;

commit;
