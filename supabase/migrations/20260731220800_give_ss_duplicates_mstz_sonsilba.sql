-- One-off operator action: give 12 copies of 'vitaming-16' (SS card) to MSTZ_손실바 as duplicate materials

begin;

do $$
declare
  v_user_id uuid;
  v_match_count integer;
begin
  select count(*), min(id::text)::uuid
  into v_match_count, v_user_id
  from public.gacha_s2_accounts
  where lower(btrim(nickname)) = lower('MSTZ_손실바');

  if v_match_count <> 1 or v_user_id is null then
    raise exception 'Expected exactly one MSTZ_손실바 account, found %', v_match_count;
  end if;

  insert into public.gacha_s2_player_cards (user_id, card_id, copies, enhancement, card_exp)
  values (v_user_id, 'vitaming-16', 12, 0, 0)
  on conflict (user_id, card_id) do update
  set copies = public.gacha_s2_player_cards.copies + 12, updated_at = now();
end;
$$;

commit;
