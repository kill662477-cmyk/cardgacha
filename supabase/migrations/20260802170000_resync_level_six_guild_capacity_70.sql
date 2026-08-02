-- Lv.6 이상 길드 정원 운영값을 70명으로 재동기화한다.
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
where level >= 6
  and member_limit <> 70;

update public.gacha_s2_guilds
set member_limit = 70,
    updated_at = now()
where level >= 6
  and disbanded_at is null
  and member_limit <> 70;

do $$
begin
  if exists (
    select 1
    from public.gacha_s2_guild_levels
    where level >= 6 and member_limit <> 70
  ) or exists (
    select 1
    from public.gacha_s2_guilds
    where level >= 6 and disbanded_at is null and member_limit <> 70
  ) then
    raise exception 'Lv.6+ guild capacity resync failed';
  end if;
end;
$$;
