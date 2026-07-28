-- One-off operator action: remove the guild rejoin penalty requested for
-- the account whose exact nickname is llliiiiiilli.

begin;

do $$
declare
  v_user_id uuid;
  v_match_count integer;
begin
  select count(*), min(id::text)::uuid
  into v_match_count, v_user_id
  from public.gacha_s2_accounts
  where lower(btrim(nickname)) = lower('llliiiiilli');

  if v_match_count <> 1 or v_user_id is null then
    raise exception 'Expected exactly one llliiiiiilli account, found %', v_match_count;
  end if;

  delete from public.gacha_s2_guild_leave_penalties
  where user_id = v_user_id;
end;
$$;

commit;
