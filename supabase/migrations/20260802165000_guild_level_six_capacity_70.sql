-- 길드 Lv.6부터 정원을 70명으로 확장한다. Lv.5는 65명 유지.
alter table public.gacha_s2_guild_levels
  drop constraint if exists gacha_s2_guild_levels_member_limit_check;
alter table public.gacha_s2_guilds
  drop constraint if exists gacha_s2_guilds_member_limit_check;

alter table public.gacha_s2_guild_levels
  add constraint gacha_s2_guild_levels_member_limit_check
  check (member_limit between 1 and 70);
alter table public.gacha_s2_guilds
  add constraint gacha_s2_guilds_member_limit_check
  check (member_limit between 1 and 70);

update public.gacha_s2_guild_levels
set member_limit = 70
where level >= 6;

update public.gacha_s2_guilds
set member_limit = greatest(member_limit, 70),
    updated_at = now()
where level >= 6
  and disbanded_at is null;

do $$
begin
  if exists (
    select 1
    from public.gacha_s2_guild_levels
    where level = 5 and member_limit <> 65
  ) then
    raise exception 'Lv.5 guild capacity must remain 65';
  end if;

  if exists (
    select 1
    from public.gacha_s2_guild_levels
    where level >= 6 and member_limit <> 70
  ) then
    raise exception 'Lv.6+ guild level capacity update failed';
  end if;

  if exists (
    select 1
    from public.gacha_s2_guilds
    where level >= 6 and disbanded_at is null and member_limit < 70
  ) then
    raise exception 'Lv.6+ active guild capacity update failed';
  end if;
end;
$$;
