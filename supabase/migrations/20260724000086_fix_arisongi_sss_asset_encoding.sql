-- Replace the Arisongi SSS PNG with a Chromium-compatible JPEG asset.

begin;
update public.gacha_s2_card_catalog
set asset_file = 'arisongi-11-r2.jpg',
    updated_at = now()
where card_id = 'arisongi-11';
update public.gacha_s2_balance_versions
set catalog_hash = '534a5b88dbdf77e0078f3e1021b4c7b255172f38bd9c0b57719998b7dd7a2b8c'
where active;
do $$
begin
  if not exists (
    select 1
    from public.gacha_s2_card_catalog
    where card_id = 'arisongi-11'
      and asset_file = 'arisongi-11-r2.jpg'
  ) then
    raise exception 'Arisongi SSS asset encoding fix validation failed';
  end if;

  if not exists (
    select 1
    from public.gacha_s2_balance_versions
    where active
      and catalog_hash = '534a5b88dbdf77e0078f3e1021b4c7b255172f38bd9c0b57719998b7dd7a2b8c'
  ) then
    raise exception 'active catalog hash refresh failed';
  end if;
end;
$$;
commit;
