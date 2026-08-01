-- Correct guild capacity to 65 members from Lv.5 onward.
-- No member is removed: deployment stops if any affected guild already exceeds 65 members.

begin;

do $preflight$
declare
  v_over_capacity integer;
begin
  select count(*)::integer
  into v_over_capacity
  from (
    select guild.guild_id
    from public.gacha_s2_guilds guild
    left join public.gacha_s2_guild_members member
      on member.guild_id = guild.guild_id
    where guild.level >= 5
    group by guild.guild_id
    having count(member.user_id) > 65
  ) over_capacity;

  if v_over_capacity > 0 then
    raise exception 'Cannot lower Lv.5+ guild capacity: % guild(s) exceed 65 members', v_over_capacity;
  end if;
end;
$preflight$;

alter table public.gacha_s2_guild_levels
  drop constraint if exists gacha_s2_guild_levels_member_limit_check;
alter table public.gacha_s2_guilds
  drop constraint if exists gacha_s2_guilds_member_limit_check;

update public.gacha_s2_guild_levels
set member_limit = 65
where level >= 5;

update public.gacha_s2_guilds
set member_limit = 65,
    updated_at = now()
where level >= 5;

alter table public.gacha_s2_guild_levels
  add constraint gacha_s2_guild_levels_member_limit_check
  check (member_limit between 1 and 65);

alter table public.gacha_s2_guilds
  add constraint gacha_s2_guilds_member_limit_check
  check (member_limit between 1 and 65);

do $verify$
begin
  if exists (
    select 1
    from public.gacha_s2_guild_levels
    where level >= 5 and member_limit <> 65
  ) then
    raise exception 'Guild level 5+ capacity correction failed';
  end if;

  if exists (
    select 1
    from public.gacha_s2_guilds
    where level >= 5 and member_limit <> 65
  ) then
    raise exception 'Existing guild capacity correction failed';
  end if;
end;
$verify$;

commit;
