-- 지두두/주하랑 SSS 카드 각 1장 추가. 로스터 235 -> 237, SSS 21 -> 23.
-- 마이그레이션 002 를 다시 돌리지 않고 범위를 좁힌 insert + catalog_hash 갱신만 한다
-- (jjiking-12 추가 때와 같은 방식). config_hash 는 그대로다 - 카드 목록만 바뀌었고
-- 이는 catalog_hash 로 따로 해시된다.
--
-- 특성은 SSS 분포가 가장 얇은 쪽으로 골랐다. 연타 2 -> 3, 생존 2 -> 3.
-- 보스는 이미 4장으로 최다라 더 늘리지 않았다.
insert into public.gacha_s2_card_catalog (
  card_id, member, asset_file, rarity, race, archetype, source_rarity, is_group, balance_version
) values
  ('jidudu-14', '지두두', 'jidudu-14.png', 'SSS', '테란', 'combo', 'FUR', false, '2026.07.30-hell10-worldboss-retune-2'),
  ('juharang-18', '주하랑', 'juharang-18.avif', 'SSS', '프로토스', 'sustain', 'FUR', false, '2026.07.30-hell10-worldboss-retune-2')
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

update public.gacha_s2_balance_versions
set catalog_hash = '230460cc91ec671cc7e36ce797624103c6a578439fe4ce623a6d878b1b5ad5e7'
where version = '2026.07.30-hell10-worldboss-retune-2' and active;

do $$
declare
  v_total integer;
  v_sss integer;
  v_hash text;
begin
  select count(*) into v_total from public.gacha_s2_card_catalog;
  if v_total <> 237 then
    raise exception 'catalog must contain exactly 237 cards, found %', v_total;
  end if;

  select count(*) into v_sss from public.gacha_s2_card_catalog where rarity = 'SSS';
  if v_sss <> 23 then
    raise exception 'SSS rarity must contain exactly 23 cards, found %', v_sss;
  end if;

  -- 등급마다 8종 특성이 다 있어야 한다. 뽑기 풀이 한쪽으로 비면 안 된다.
  if exists (
    select 1 from public.gacha_s2_card_catalog
    where rarity <> 'EX'
    group by rarity
    having count(distinct archetype) <> 8
  ) then
    raise exception 'every combat rarity must contain all 8 archetypes';
  end if;

  select catalog_hash into v_hash
  from public.gacha_s2_balance_versions
  where version = '2026.07.30-hell10-worldboss-retune-2' and active;
  if v_hash is distinct from '230460cc91ec671cc7e36ce797624103c6a578439fe4ce623a6d878b1b5ad5e7' then
    raise exception 'catalog hash mismatch: %', v_hash;
  end if;
end;
$$;
