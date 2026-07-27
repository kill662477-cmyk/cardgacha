-- One-off operator action: give 10 quickBattleReset items to MSTZ_손실바

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

  update public.gacha_s2_player_states
  set support_items = coalesce(support_items, '{}'::jsonb) || jsonb_build_object(
      'quickBattleReset', coalesce((support_items->>'quickBattleReset')::int, 0) + 10
  ),
  updated_at = now()
  where user_id = v_user_id;
end;
$$;

commit;
