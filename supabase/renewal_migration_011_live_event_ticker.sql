-- Card Gacha Season 2: public high-rarity draw and +9 enhancement live feed.
-- Run after migration 010. Events contain display-safe public fields only.

begin;

do $$
begin
  if to_regclass('public.gacha_s2_accounts') is null
    or to_regclass('public.gacha_s2_card_catalog') is null
    or to_regclass('public.gacha_s2_pack_draws') is null
    or to_regclass('public.gacha_s2_enhancement_results') is null then
    raise exception 'missing Season 2 source tables: run migrations 001-010 first';
  end if;
end;
$$;

create table if not exists public.gacha_s2_live_events (
  id bigint generated always as identity primary key,
  source_key text not null unique check (source_key ~ '^[0-9a-f]{64}$'),
  event_type text not null check (event_type in ('card_draw','nine_star_success')),
  nickname text not null check (length(trim(nickname)) between 1 and 40),
  card_id text not null references public.gacha_s2_card_catalog(card_id),
  member text not null check (length(trim(member)) between 1 and 40),
  rarity text not null check (rarity in ('F','E','D','C','B','A','S','SS','SSS')),
  enhancement integer check (enhancement is null or enhancement between 0 and 9),
  created_at timestamptz not null default now(),
  check (
    (event_type = 'card_draw' and rarity in ('S','SS','SSS') and enhancement is null)
    or (event_type = 'nine_star_success' and enhancement = 9)
  )
);

create index if not exists idx_gacha_s2_live_events_created
  on public.gacha_s2_live_events(created_at desc);

alter table public.gacha_s2_live_events enable row level security;
drop policy if exists gacha_s2_live_events_recent_read on public.gacha_s2_live_events;
create policy gacha_s2_live_events_recent_read
  on public.gacha_s2_live_events
  for select
  to authenticated
  using (created_at >= now() - interval '10 minutes');

create or replace function public.gacha_s2_emit_pack_live_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nickname text;
  v_member text;
begin
  if new.rarity not in ('S','SS','SSS') then return new; end if;
  select account.nickname, catalog.member
  into v_nickname, v_member
  from public.gacha_s2_accounts account
  join public.gacha_s2_card_catalog catalog on catalog.card_id = new.card_id
  where account.id = new.user_id;

  if v_nickname is null or v_member is null then return new; end if;
  insert into public.gacha_s2_live_events (
    source_key, event_type, nickname, card_id, member, rarity, enhancement, created_at
  ) values (
    encode(digest('pack:' || new.id::text, 'sha256'), 'hex'),
    'card_draw', v_nickname, new.card_id, v_member, new.rarity, null, new.created_at
  )
  on conflict (source_key) do nothing;
  return new;
end;
$$;

create or replace function public.gacha_s2_emit_enhancement_live_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nickname text;
  v_member text;
  v_rarity text;
begin
  if new.outcome <> 'success' or new.target_enhancement <> 9 or new.final_enhancement <> 9 then return new; end if;
  select account.nickname, catalog.member, catalog.rarity
  into v_nickname, v_member, v_rarity
  from public.gacha_s2_accounts account
  join public.gacha_s2_card_catalog catalog on catalog.card_id = new.card_id
  where account.id = new.user_id;

  if v_nickname is null or v_member is null or v_rarity = 'EX' then return new; end if;
  insert into public.gacha_s2_live_events (
    source_key, event_type, nickname, card_id, member, rarity, enhancement, created_at
  ) values (
    encode(digest('enhance:' || new.id::text, 'sha256'), 'hex'),
    'nine_star_success', v_nickname, new.card_id, v_member, v_rarity, 9, new.created_at
  )
  on conflict (source_key) do nothing;
  return new;
end;
$$;

drop trigger if exists gacha_s2_pack_draw_live_event on public.gacha_s2_pack_draws;
create trigger gacha_s2_pack_draw_live_event
after insert on public.gacha_s2_pack_draws
for each row execute function public.gacha_s2_emit_pack_live_event();

drop trigger if exists gacha_s2_enhancement_live_event on public.gacha_s2_enhancement_results;
create trigger gacha_s2_enhancement_live_event
after insert on public.gacha_s2_enhancement_results
for each row execute function public.gacha_s2_emit_enhancement_live_event();

insert into public.gacha_s2_live_events (
  source_key, event_type, nickname, card_id, member, rarity, enhancement, created_at
)
select
  encode(digest('pack:' || draw.id::text, 'sha256'), 'hex'),
  'card_draw', account.nickname, draw.card_id, catalog.member, draw.rarity, null, draw.created_at
from public.gacha_s2_pack_draws draw
join public.gacha_s2_accounts account on account.id = draw.user_id
join public.gacha_s2_card_catalog catalog on catalog.card_id = draw.card_id
where draw.rarity in ('S','SS','SSS')
  and draw.created_at >= now() - interval '10 minutes'
on conflict (source_key) do nothing;

insert into public.gacha_s2_live_events (
  source_key, event_type, nickname, card_id, member, rarity, enhancement, created_at
)
select
  encode(digest('enhance:' || result.id::text, 'sha256'), 'hex'),
  'nine_star_success', account.nickname, result.card_id, catalog.member, catalog.rarity, 9, result.created_at
from public.gacha_s2_enhancement_results result
join public.gacha_s2_accounts account on account.id = result.user_id
join public.gacha_s2_card_catalog catalog on catalog.card_id = result.card_id
where result.outcome = 'success'
  and result.target_enhancement = 9
  and result.final_enhancement = 9
  and result.created_at >= now() - interval '10 minutes'
on conflict (source_key) do nothing;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'gacha_s2_live_events'
    ) then
    alter publication supabase_realtime add table public.gacha_s2_live_events;
  end if;
end;
$$;

revoke all on table public.gacha_s2_live_events from public, anon, authenticated;
grant select on table public.gacha_s2_live_events to authenticated;
revoke all on function public.gacha_s2_emit_pack_live_event() from public, anon, authenticated;
revoke all on function public.gacha_s2_emit_enhancement_live_event() from public, anon, authenticated;

commit;

