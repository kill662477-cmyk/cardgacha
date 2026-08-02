-- Mstz_손실바 계정에 랜덤특성변경권 3개 지급

begin;

do $$
declare
  v_user_id uuid;
begin
  select id into v_user_id from public.gacha_s2_accounts
  where lower(btrim(nickname)) = lower('MSTZ_손실바')
  limit 1;

  if v_user_id is not null then
    update public.gacha_s2_player_states
    set support_items = jsonb_set(
      coalesce(support_items, '{}'::jsonb),
      '{traitReroll}',
      to_jsonb(coalesce((support_items->>'traitReroll')::integer, 0) + 3),
      true
    ),
    revision = revision + 1,
    updated_at = now()
    where user_id = v_user_id;
  end if;
end;
$$;

commit;
