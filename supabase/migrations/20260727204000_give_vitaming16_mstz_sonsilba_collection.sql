-- One-off operator action: add vitaming-16 to MSTZ_손실바's collection records and bump revision

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

  insert into public.gacha_s2_collection_records (user_id, card_id, first_acquired_at)
  values (v_user_id, 'vitaming-16', now())
  on conflict (user_id, card_id) do nothing;

  update public.gacha_s2_player_states
  set revision = revision + 1,
      updated_at = now()
  where user_id = v_user_id;

end;
$$;

commit;
