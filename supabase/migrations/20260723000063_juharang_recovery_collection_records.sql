-- Register enhancement-recovery target cards in the collection book.

begin;

insert into public.gacha_s2_collection_records (user_id, card_id, first_acquired_at)
select recovery.user_id, recovery.target_card_id, recovery.recovered_at
from public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
join public.gacha_s2_player_cards owned
  on owned.user_id = recovery.user_id
 and owned.card_id = recovery.target_card_id
on conflict (user_id, card_id) do nothing;

update public.gacha_s2_player_states state
set revision = state.revision + 1,
    updated_at = now()
where exists (
  select 1
  from public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
  where recovery.user_id = state.user_id
);

do $$
begin
  if exists (
    select 1
    from public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
    left join public.gacha_s2_collection_records collection
      on collection.user_id = recovery.user_id
     and collection.card_id = recovery.target_card_id
    where collection.user_id is null
  ) then
    raise exception 'Juharang recovery collection registration validation failed';
  end if;
end;
$$;

commit;
