-- One-off operator action: give Mstz_손실바 full collection, fill formation, and give 150,000 points.

begin;

do $$
declare
  v_user_id uuid;
  v_match_count integer;
  v_formation text[];
begin
  select count(*), min(id::text)::uuid
  into v_match_count, v_user_id
  from public.gacha_s2_accounts
  where lower(btrim(nickname)) = lower('MSTZ_손실바');

  if v_match_count <> 1 or v_user_id is null then
    raise exception 'Expected exactly one MSTZ_손실바 account, found %', v_match_count;
  end if;

  -- 1. Give 150,000 P
  update public.gacha_s2_player_states
  set points = points + 150000,
      revision = revision + 1,
      updated_at = now()
  where user_id = v_user_id;

  -- 2. Fill collection (insert into player_cards and collection_records)
  insert into public.gacha_s2_player_cards (user_id, card_id, copies, enhancement, card_exp)
  select v_user_id, card_id, 1, 0, 0
  from public.gacha_s2_card_catalog
  on conflict (user_id, card_id) do update
  set copies = public.gacha_s2_player_cards.copies + 1, updated_at = now();

  insert into public.gacha_s2_collection_records (user_id, card_id, first_acquired_at)
  select v_user_id, card_id, now()
  from public.gacha_s2_card_catalog
  on conflict (user_id, card_id) do nothing;

  -- 3. Fill formation with 5 best cards
  select array_agg(card_id) into v_formation
  from (
    select card_id from public.gacha_s2_card_catalog
    where not is_group
    order by 
      case rarity 
        when 'EX' then 1 
        when 'SSS' then 2 
        when 'SS' then 3 
        else 4 
      end, 
      card_id
    limit 5
  ) sub;

  update public.gacha_s2_player_states
  set formation = v_formation,
      revision = revision + 1,
      updated_at = now()
  where user_id = v_user_id;

end;
$$;

commit;
