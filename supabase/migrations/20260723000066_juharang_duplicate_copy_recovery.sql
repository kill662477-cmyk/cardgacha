-- Remove legacy low-rarity duplicate inflation from Juharang 3/4 after their SS promotion.
-- Keep one promoted SS copy plus every legitimate post-refresh acquisition.
-- Return legacy excess copies, including copies consumed as enhancement materials or dismantled,
-- to cards of the original rarity: Juharang 3(E)->13(E), Juharang 4(B)->9(B).

begin;

lock table public.gacha_s2_player_cards,
  public.gacha_s2_player_states,
  public.gacha_s2_collection_records,
  public.gacha_s2_pack_draws,
  public.gacha_s2_enhancement_results,
  public.gacha_s2_idempotency
in share row exclusive mode;

do $$
begin
  if (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-3') <> 'SS'
    or (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-4') <> 'SS'
    or (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-13') <> 'E'
    or (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-9') <> 'B' then
    raise exception 'Juharang duplicate recovery rarity mapping mismatch';
  end if;
end;
$$;

create table if not exists public.gacha_s2_juharang_duplicate_recovery_20260723 (
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  source_card_id text not null,
  target_card_id text not null,
  source_copies_before integer not null,
  target_copies_before integer,
  post_refresh_acquired integer not null,
  enhancement_materials_refunded integer not null,
  dismantled_copies_refunded integer not null,
  existing_copies_moved integer not null,
  total_legacy_excess_restored integer not null,
  source_copies_after integer,
  target_copies_after integer,
  recovered_at timestamptz not null default now(),
  primary key (user_id, source_card_id)
);

with refresh_cutoff as (
  select updated_at
  from public.gacha_s2_card_catalog
  where card_id = 'juharang-3'
),
recovery_map(source_card_id, target_card_id) as (
  values
    ('juharang-3'::text, 'juharang-13'::text),
    ('juharang-4'::text, 'juharang-9'::text)
),
post_refresh_draws as (
  select draw.user_id, draw.card_id, count(*)::integer as copies
  from public.gacha_s2_pack_draws draw
  cross join refresh_cutoff cutoff
  where draw.card_id in ('juharang-3', 'juharang-4')
    and draw.created_at >= cutoff.updated_at
  group by draw.user_id, draw.card_id
),
recovery_acquisitions as (
  select recovery.user_id, recovery.target_card_id as card_id, count(*)::integer as copies
  from public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
  where recovery.target_card_id in ('juharang-3', 'juharang-4')
    and not recovery.target_existed
  group by recovery.user_id, recovery.target_card_id
),
post_refresh_acquisitions as (
  select user_id, card_id, sum(copies)::integer as copies
  from (
    select * from post_refresh_draws
    union all
    select * from recovery_acquisitions
  ) acquired
  group by user_id, card_id
),
enhancement_consumption as (
  select result.user_id, material.card_id, count(*)::integer as copies
  from public.gacha_s2_enhancement_results result
  cross join refresh_cutoff cutoff
  cross join lateral jsonb_array_elements_text(result.materials) as material(card_id)
  where result.created_at >= cutoff.updated_at
    and material.card_id in ('juharang-3', 'juharang-4')
  group by result.user_id, material.card_id
),
dismantle_consumption as (
  select replay.user_id,
    roll.value->>'cardId' as card_id,
    sum((roll.value->>'dismantled')::integer)::integer as copies
  from public.gacha_s2_idempotency replay
  cross join refresh_cutoff cutoff
  cross join lateral jsonb_array_elements(coalesce(replay.response->'result'->'rolls', '[]'::jsonb)) as roll(value)
  where replay.command_type = 'dismantleCards'
    and replay.created_at >= cutoff.updated_at
    and roll.value->>'cardId' in ('juharang-3', 'juharang-4')
  group by replay.user_id, roll.value->>'cardId'
),
reconstructed as (
  select
    source.user_id,
    source.card_id as source_card_id,
    recovery_map.target_card_id,
    source.copies as source_copies_before,
    target.copies as target_copies_before,
    coalesce(acquired.copies, 0) as post_refresh_acquired,
    coalesce(enhancement.copies, 0) as enhancement_materials_refunded,
    coalesce(dismantled.copies, 0) as dismantled_copies_refunded,
    greatest(0, source.copies - coalesce(acquired.copies, 0) - 1) as existing_copies_moved,
    greatest(
      0,
      source.copies
        - coalesce(acquired.copies, 0)
        + coalesce(enhancement.copies, 0)
        + coalesce(dismantled.copies, 0)
        - 1
    ) as total_legacy_excess_restored
  from recovery_map
  join public.gacha_s2_player_cards source
    on source.card_id = recovery_map.source_card_id
  left join public.gacha_s2_player_cards target
    on target.user_id = source.user_id
   and target.card_id = recovery_map.target_card_id
  left join post_refresh_acquisitions acquired
    on acquired.user_id = source.user_id
   and acquired.card_id = source.card_id
  left join enhancement_consumption enhancement
    on enhancement.user_id = source.user_id
   and enhancement.card_id = source.card_id
  left join dismantle_consumption dismantled
    on dismantled.user_id = source.user_id
   and dismantled.card_id = source.card_id
)
insert into public.gacha_s2_juharang_duplicate_recovery_20260723 (
  user_id,
  source_card_id,
  target_card_id,
  source_copies_before,
  target_copies_before,
  post_refresh_acquired,
  enhancement_materials_refunded,
  dismantled_copies_refunded,
  existing_copies_moved,
  total_legacy_excess_restored
)
select
  user_id,
  source_card_id,
  target_card_id,
  source_copies_before,
  target_copies_before,
  post_refresh_acquired,
  enhancement_materials_refunded,
  dismantled_copies_refunded,
  existing_copies_moved,
  total_legacy_excess_restored
from reconstructed
where total_legacy_excess_restored > 0
on conflict (user_id, source_card_id) do nothing;

update public.gacha_s2_player_cards source
set copies = source.copies - recovery.existing_copies_moved,
    updated_at = now()
from public.gacha_s2_juharang_duplicate_recovery_20260723 recovery
where source.user_id = recovery.user_id
  and source.card_id = recovery.source_card_id;

insert into public.gacha_s2_player_cards (
  user_id,
  card_id,
  copies,
  enhancement,
  card_exp,
  locked,
  first_acquired_at,
  updated_at
)
select
  recovery.user_id,
  recovery.target_card_id,
  recovery.total_legacy_excess_restored,
  0,
  0,
  source.locked,
  source.first_acquired_at,
  now()
from public.gacha_s2_juharang_duplicate_recovery_20260723 recovery
join public.gacha_s2_player_cards source
  on source.user_id = recovery.user_id
 and source.card_id = recovery.source_card_id
on conflict (user_id, card_id) do update
set copies = public.gacha_s2_player_cards.copies + excluded.copies,
    locked = public.gacha_s2_player_cards.locked or excluded.locked,
    first_acquired_at = least(public.gacha_s2_player_cards.first_acquired_at, excluded.first_acquired_at),
    updated_at = now();

insert into public.gacha_s2_collection_records (user_id, card_id, first_acquired_at)
select recovery.user_id, recovery.target_card_id, source.first_acquired_at
from public.gacha_s2_juharang_duplicate_recovery_20260723 recovery
join public.gacha_s2_player_cards source
  on source.user_id = recovery.user_id
 and source.card_id = recovery.source_card_id
on conflict (user_id, card_id) do update
set first_acquired_at = least(
  public.gacha_s2_collection_records.first_acquired_at,
  excluded.first_acquired_at
);

update public.gacha_s2_juharang_duplicate_recovery_20260723 recovery
set source_copies_after = source.copies,
    target_copies_after = target.copies
from public.gacha_s2_player_cards source,
  public.gacha_s2_player_cards target
where source.user_id = recovery.user_id
  and source.card_id = recovery.source_card_id
  and target.user_id = recovery.user_id
  and target.card_id = recovery.target_card_id;

update public.gacha_s2_player_states state
set revision = state.revision + 1,
    updated_at = now()
where exists (
  select 1
  from public.gacha_s2_juharang_duplicate_recovery_20260723 recovery
  where recovery.user_id = state.user_id
);

do $$
begin
  if exists (
    select 1
    from public.gacha_s2_juharang_duplicate_recovery_20260723 recovery
    where recovery.source_copies_after is null
       or recovery.target_copies_after is null
       or recovery.source_copies_after <> least(
         recovery.source_copies_before,
         recovery.post_refresh_acquired + 1
       )
       or recovery.target_copies_after <> coalesce(recovery.target_copies_before, 0)
         + recovery.total_legacy_excess_restored
       or recovery.total_legacy_excess_restored < recovery.enhancement_materials_refunded
         + recovery.dismantled_copies_refunded
  ) then
    raise exception 'Juharang duplicate copy recovery validation failed';
  end if;
end;
$$;

revoke all on table public.gacha_s2_juharang_duplicate_recovery_20260723
  from public, anon, authenticated;

commit;
