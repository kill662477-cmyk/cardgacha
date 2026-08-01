-- Expand guild capacity to 70 members from Lv.5 onward.
-- Existing active Lv.5+ guilds are updated immediately when this migration is deployed.

begin;

do $preflight$
declare
  v_target_guilds integer;
begin
  select count(*)::integer into v_target_guilds
  from public.gacha_s2_guilds
  where level >= 5 and disbanded_at is null;

  raise notice 'Guild Lv.5+ capacity targets: % active guild(s)', v_target_guilds;
end;
$preflight$;

alter table public.gacha_s2_guild_levels
  drop constraint if exists gacha_s2_guild_levels_member_limit_check;
alter table public.gacha_s2_guild_levels
  add constraint gacha_s2_guild_levels_member_limit_check
  check (member_limit between 1 and 70);

alter table public.gacha_s2_guilds
  drop constraint if exists gacha_s2_guilds_member_limit_check;
alter table public.gacha_s2_guilds
  add constraint gacha_s2_guilds_member_limit_check
  check (member_limit between 1 and 70);

update public.gacha_s2_guild_levels
set member_limit = 70
where level >= 5;

update public.gacha_s2_guilds
set member_limit = greatest(member_limit, 70),
    updated_at = now()
where level >= 5 and disbanded_at is null;

do $verify$
begin
  if exists (
    select 1
    from public.gacha_s2_guild_levels
    where level >= 5 and member_limit <> 70
  ) then
    raise exception 'Guild level 5+ capacity update failed';
  end if;

  if exists (
    select 1
    from public.gacha_s2_guilds
    where level >= 5 and disbanded_at is null and member_limit < 70
  ) then
    raise exception 'Existing guild capacity update failed';
  end if;
end;
$verify$;

commit;
