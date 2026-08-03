-- Mstz_손실바 랜덤특성변경권 3장 지급 (5회차)

begin;

do $$
declare
  v_target_id uuid;
begin
  select id into v_target_id
  from public.gacha_s2_accounts
  where nickname = 'Mstz_손실바';

  if v_target_id is null then
    raise exception 'target user Mstz_sonsilba not found';
  end if;

  update public.gacha_s2_player_states
  set support_items = jsonb_set(
        coalesce(support_items, '{}'::jsonb),
        '{traitReroll}',
        to_jsonb(coalesce((support_items->>'traitReroll')::integer, 0) + 3),
        true
      ),
      revision = revision + 1,
      updated_at = now()
  where user_id = v_target_id;
end;
$$;

commit;
