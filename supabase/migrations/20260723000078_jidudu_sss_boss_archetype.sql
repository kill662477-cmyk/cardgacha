-- Change only the Jidudu SSS card from quick to boss archetype.
begin;
update public.gacha_s2_card_catalog
set archetype = 'boss',
    balance_version = (
      select version
      from public.gacha_s2_balance_versions
      where active
      limit 1
    ),
    updated_at = now()
where card_id = 'jidudu-1'
  and member = '지두두'
  and rarity = 'SSS';
update public.gacha_s2_balance_versions
set catalog_hash = 'b65081b831be5ec27191588a758ec1ddcc3b6f311b65f9c6fc4a4e6755225289'
where active;
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.gacha_s2_card_catalog
  where card_id = 'jidudu-1'
    and member = '지두두'
    and rarity = 'SSS'
    and archetype = 'boss';
  if v_count <> 1 then
    raise exception 'jidudu-1 SSS boss archetype update failed';
  end if;
end;
$$;
commit;
