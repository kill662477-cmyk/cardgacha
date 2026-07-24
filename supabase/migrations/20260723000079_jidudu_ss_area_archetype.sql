-- Change only the Jidudu SS card shown in the archive from heavy to area.
begin;
update public.gacha_s2_card_catalog
set archetype = 'area',
    balance_version = (
      select version
      from public.gacha_s2_balance_versions
      where active
      limit 1
    ),
    updated_at = now()
where card_id = 'jidudu-9'
  and member = '지두두'
  and rarity = 'SS';
update public.gacha_s2_balance_versions
set catalog_hash = '1515a601b1945f06ca933d6270030223237cccb0e14c97c049ef8597c604fbc2'
where active;
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.gacha_s2_card_catalog
  where card_id = 'jidudu-9'
    and member = '지두두'
    and rarity = 'SS'
    and archetype = 'area';
  if v_count <> 1 then
    raise exception 'jidudu-9 SS area archetype update failed';
  end if;
end;
$$;
commit;
