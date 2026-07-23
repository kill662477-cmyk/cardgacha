-- Complete linked-state recovery for the compensated Juharang cards.
-- Historical draw, enhancement, adventure, and world-boss audit rows stay immutable.

begin;

create table if not exists public.gacha_s2_juharang_linked_state_backup_20260723 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  formation_before text[] not null,
  formation_presets_before jsonb not null,
  representative_card_id_before text,
  power_snapshot_before integer not null,
  power_snapshot_at_before timestamptz,
  card_locks_before jsonb not null,
  backed_up_at timestamptz not null default now()
);

insert into public.gacha_s2_juharang_linked_state_backup_20260723 (
  user_id,
  formation_before,
  formation_presets_before,
  representative_card_id_before,
  power_snapshot_before,
  power_snapshot_at_before,
  card_locks_before
)
select
  state.user_id,
  state.formation,
  state.formation_presets,
  state.representative_card_id,
  state.power_snapshot,
  state.power_snapshot_at,
  coalesce((
    select jsonb_object_agg(owned.card_id, owned.locked)
    from public.gacha_s2_player_cards owned
    where owned.user_id = state.user_id
      and owned.card_id in (
        'juharang-10', 'juharang-11', 'juharang-12',
        'juharang-17', 'juharang-1', 'juharang-3'
      )
  ), '{}'::jsonb)
from public.gacha_s2_player_states state
where exists (
  select 1
  from public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
  where recovery.user_id = state.user_id
)
on conflict (user_id) do nothing;

update public.gacha_s2_player_cards target
set locked = target.locked or source.locked,
    first_acquired_at = least(target.first_acquired_at, source.first_acquired_at),
    updated_at = now()
from public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
join public.gacha_s2_player_cards source
  on source.user_id = recovery.user_id
 and source.card_id = recovery.source_card_id
where target.user_id = recovery.user_id
  and target.card_id = recovery.target_card_id;

update public.gacha_s2_collection_records collection
set first_acquired_at = least(collection.first_acquired_at, source.first_acquired_at)
from public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
join public.gacha_s2_player_cards source
  on source.user_id = recovery.user_id
 and source.card_id = recovery.source_card_id
where collection.user_id = recovery.user_id
  and collection.card_id = recovery.target_card_id;

with mapped_formations as (
  select
    state.user_id,
    array_agg(coalesce(recovery.target_card_id, slot.card_id) order by slot.ordinality)::text[] as formation
  from public.gacha_s2_player_states state
  cross join lateral unnest(state.formation) with ordinality as slot(card_id, ordinality)
  left join public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
    on recovery.user_id = state.user_id
   and recovery.source_card_id = slot.card_id
  where exists (
    select 1
    from public.gacha_s2_juharang_enhancement_recovery_20260723 affected
    where affected.user_id = state.user_id
      and affected.source_card_id = any(state.formation)
  )
  group by state.user_id
)
update public.gacha_s2_player_states state
set formation = mapped.formation,
    updated_at = now()
from mapped_formations mapped
where state.user_id = mapped.user_id;

update public.gacha_s2_player_states state
set representative_card_id = recovery.target_card_id,
    updated_at = now()
from public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
where state.user_id = recovery.user_id
  and state.representative_card_id = recovery.source_card_id;

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
    join public.gacha_s2_player_cards source
      on source.user_id = recovery.user_id
     and source.card_id = recovery.source_card_id
    join public.gacha_s2_player_cards target
      on target.user_id = recovery.user_id
     and target.card_id = recovery.target_card_id
    join public.gacha_s2_collection_records collection
      on collection.user_id = recovery.user_id
     and collection.card_id = recovery.target_card_id
    where (source.locked and not target.locked)
       or target.first_acquired_at > source.first_acquired_at
       or collection.first_acquired_at > source.first_acquired_at
  ) then
    raise exception 'Juharang linked card state recovery validation failed';
  end if;

  if exists (
    select 1
    from public.gacha_s2_player_states state
    join public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
      on recovery.user_id = state.user_id
    where recovery.source_card_id = any(state.formation)
       or state.representative_card_id = recovery.source_card_id
       or cardinality(state.formation) <> (
         select count(distinct card_id)
         from unnest(state.formation) as cards(card_id)
       )
  ) then
    raise exception 'Juharang formation or representative recovery validation failed';
  end if;
end;
$$;

revoke all on table public.gacha_s2_juharang_linked_state_backup_20260723
  from public, anon, authenticated;

commit;
