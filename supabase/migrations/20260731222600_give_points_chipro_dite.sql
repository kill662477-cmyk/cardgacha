-- One-off operator action: give 600,000 P to 치프로디테

begin;

do $$
declare
  v_user_id uuid;
  v_match_count integer;
begin
  select count(*), min(id::text)::uuid
  into v_match_count, v_user_id
  from public.gacha_s2_accounts
  where lower(btrim(nickname)) = lower('치프로디테');

  if v_match_count <> 1 or v_user_id is null then
    raise exception 'Expected exactly one 치프로디테 account, found %', v_match_count;
  end if;

  update public.gacha_s2_player_states
  set points = points + 600000,
      revision = revision + 1,
      updated_at = now()
  where user_id = v_user_id;

end;
$$;

commit;
