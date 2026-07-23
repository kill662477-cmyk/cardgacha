-- Preserve enhancement investments made on Juharang cards whose rarity was lowered.
-- Recovery mapping keeps the pre-refresh rarity: 10(S)->17(S), 11(C)->1(C), 12(SS)->3(SS).

begin;

do $$
begin
  if (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-17') <> 'S'
    or (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-1') <> 'C'
    or (select rarity from public.gacha_s2_card_catalog where card_id = 'juharang-3') <> 'SS' then
    raise exception 'Juharang enhancement recovery target rarity mismatch';
  end if;
end;
$$;

create table if not exists public.gacha_s2_juharang_enhancement_recovery_20260723 (
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  source_card_id text not null,
  target_card_id text not null,
  source_copies integer not null,
  source_enhancement integer not null,
  source_card_exp integer not null,
  target_existed boolean not null,
  target_copies_before integer,
  target_enhancement_before integer,
  target_card_exp_before integer,
  final_copies integer,
  final_enhancement integer,
  final_card_exp integer,
  recovered_at timestamptz not null default now(),
  primary key (user_id, source_card_id)
);

with recovery_map(source_card_id, target_card_id) as (
  values
    ('juharang-10'::text, 'juharang-17'::text),
    ('juharang-11'::text, 'juharang-1'::text),
    ('juharang-12'::text, 'juharang-3'::text)
)
insert into public.gacha_s2_juharang_enhancement_recovery_20260723 (
  user_id,
  source_card_id,
  target_card_id,
  source_copies,
  source_enhancement,
  source_card_exp,
  target_existed,
  target_copies_before,
  target_enhancement_before,
  target_card_exp_before
)
select
  source.user_id,
  source.card_id,
  recovery_map.target_card_id,
  source.copies,
  source.enhancement,
  source.card_exp,
  target.user_id is not null,
  target.copies,
  target.enhancement,
  target.card_exp
from recovery_map
join public.gacha_s2_player_cards source
  on source.card_id = recovery_map.source_card_id
left join public.gacha_s2_player_cards target
  on target.user_id = source.user_id
 and target.card_id = recovery_map.target_card_id
where source.enhancement > 0 or source.card_exp > 0
on conflict (user_id, source_card_id) do nothing;

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
  1,
  recovery.source_enhancement,
  recovery.source_card_exp,
  false,
  now(),
  now()
from public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
on conflict (user_id, card_id) do update
set enhancement = greatest(
      public.gacha_s2_player_cards.enhancement,
      excluded.enhancement
    ),
    card_exp = case
      when excluded.enhancement > public.gacha_s2_player_cards.enhancement then excluded.card_exp
      when excluded.enhancement < public.gacha_s2_player_cards.enhancement then public.gacha_s2_player_cards.card_exp
      else greatest(public.gacha_s2_player_cards.card_exp, excluded.card_exp)
    end,
    updated_at = now();

update public.gacha_s2_juharang_enhancement_recovery_20260723 recovery
set final_copies = target.copies,
    final_enhancement = target.enhancement,
    final_card_exp = target.card_exp
from public.gacha_s2_player_cards target
where target.user_id = recovery.user_id
  and target.card_id = recovery.target_card_id;

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
    where recovery.final_enhancement is null
       or recovery.final_enhancement < recovery.source_enhancement
       or (
         recovery.final_enhancement = recovery.source_enhancement
         and recovery.final_card_exp < recovery.source_card_exp
       )
  ) then
    raise exception 'Juharang enhancement recovery validation failed';
  end if;
end;
$$;

revoke all on table public.gacha_s2_juharang_enhancement_recovery_20260723
  from public, anon, authenticated;

commit;
