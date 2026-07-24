-- Refresh the three new SSS asset paths to bypass stale missing-image caches.

begin;
update public.gacha_s2_card_catalog
set asset_file = case card_id
      when 'byeonhyeonje-7' then 'byeonhyeonje-7-r1.jpg'
      when 'sate-5' then 'sate-5-r1.png'
      when 'arisongi-11' then 'arisongi-11-r1.png'
    end,
    updated_at = now()
where card_id in ('byeonhyeonje-7', 'sate-5', 'arisongi-11');
update public.gacha_s2_balance_versions
set catalog_hash = '0d87eaa96fb9288b51cd3bcf4414f592b5faca7cefc6600998021f6d9bc73b92'
where active;
do $$
begin
  if (
    select count(*)
    from public.gacha_s2_card_catalog
    where (card_id, asset_file) in (
      ('byeonhyeonje-7', 'byeonhyeonje-7-r1.jpg'),
      ('sate-5', 'sate-5-r1.png'),
      ('arisongi-11', 'arisongi-11-r1.png')
    )
  ) <> 3 then
    raise exception 'new SSS asset path refresh validation failed';
  end if;
  if not exists (
    select 1
    from public.gacha_s2_balance_versions
    where active
      and catalog_hash = '0d87eaa96fb9288b51cd3bcf4414f592b5faca7cefc6600998021f6d9bc73b92'
  ) then
    raise exception 'active catalog hash refresh failed';
  end if;
end;
$$;
commit;
