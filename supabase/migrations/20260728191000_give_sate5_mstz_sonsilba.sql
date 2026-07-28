-- One-off operator action: give one sate-5 (사테 SSS) card to Mstz_손실바.
-- The grant ledger makes the operation safe to retry without adding duplicates.

begin;

create table if not exists public.gacha_s2_operator_card_grants (
  grant_key text primary key,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  card_id text not null references public.gacha_s2_card_catalog(card_id),
  copies integer not null check (copies > 0),
  granted_at timestamptz not null default now()
);

alter table public.gacha_s2_operator_card_grants enable row level security;
revoke all on table public.gacha_s2_operator_card_grants from public, anon, authenticated;
grant select on table public.gacha_s2_operator_card_grants to service_role;

do $$
declare
  v_user_id uuid;
  v_match_count integer;
  v_catalog_count integer;
  v_new_grant integer;
  v_state_updates integer;
begin
  select count(*), min(id::text)::uuid
  into v_match_count, v_user_id
  from public.gacha_s2_accounts
  where lower(btrim(nickname)) = lower('Mstz_손실바');

  if v_match_count <> 1 or v_user_id is null then
    raise exception 'Expected exactly one Mstz_손실바 account, found %', v_match_count;
  end if;

  select count(*)
  into v_catalog_count
  from public.gacha_s2_card_catalog
  where card_id = 'sate-5'
    and member = '사테'
    and rarity = 'SSS';

  if v_catalog_count <> 1 then
    raise exception 'Expected sate-5 to be exactly one 사테 SSS catalog card, found %', v_catalog_count;
  end if;

  insert into public.gacha_s2_operator_card_grants (grant_key, user_id, card_id, copies)
  values ('operator:20260728:mstz-sate5', v_user_id, 'sate-5', 1)
  on conflict (grant_key) do nothing;
  get diagnostics v_new_grant = row_count;

  if v_new_grant = 1 then
    insert into public.gacha_s2_player_cards (user_id, card_id, copies, enhancement, card_exp)
    values (v_user_id, 'sate-5', 1, 0, 0)
    on conflict (user_id, card_id) do update
    set copies = public.gacha_s2_player_cards.copies + excluded.copies,
        updated_at = now();

    insert into public.gacha_s2_collection_records (user_id, card_id, first_acquired_at)
    values (v_user_id, 'sate-5', now())
    on conflict (user_id, card_id) do nothing;

    update public.gacha_s2_player_states
    set revision = revision + 1,
        updated_at = now()
    where user_id = v_user_id;
    get diagnostics v_state_updates = row_count;

    if v_state_updates <> 1 then
      raise exception 'Expected one player state update for Mstz_손실바, found %', v_state_updates;
    end if;
  end if;

  if not exists (
    select 1
    from public.gacha_s2_operator_card_grants
    where grant_key = 'operator:20260728:mstz-sate5'
      and user_id = v_user_id
      and card_id = 'sate-5'
      and copies = 1
  ) then
    raise exception 'Operator grant ledger validation failed';
  end if;

  if not exists (
    select 1
    from public.gacha_s2_player_cards
    where user_id = v_user_id
      and card_id = 'sate-5'
      and copies >= 1
  ) then
    raise exception 'sate-5 inventory grant validation failed';
  end if;

  if not exists (
    select 1
    from public.gacha_s2_collection_records
    where user_id = v_user_id
      and card_id = 'sate-5'
  ) then
    raise exception 'sate-5 collection record validation failed';
  end if;
end;
$$;

commit;
