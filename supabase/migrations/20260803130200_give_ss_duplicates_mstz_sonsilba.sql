-- Mstz_손실바 계정에 SS중복카드 21장 지급 (kimmincheol-3 카드 사본 추가)

begin;

do $$
declare
  v_target_id uuid;
begin
  select id into v_target_id
  from public.gacha_s2_accounts
  where nickname = 'Mstz_손실바';

  if v_target_id is null then
    raise exception 'target user Mstz_손실바 not found';
  end if;

  update public.gacha_s2_player_cards
  set copies = copies + 21,
      updated_at = now()
  where user_id = v_target_id and card_id = 'kimmincheol-3';

  update public.gacha_s2_player_states
  set revision = revision + 1,
      updated_at = now()
  where user_id = v_target_id;
end;
$$;

commit;
