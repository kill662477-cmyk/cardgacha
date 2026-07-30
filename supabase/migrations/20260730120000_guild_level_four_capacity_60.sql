-- 길드 Lv.4부터 정원을 60명으로 확장한다.
-- 기존 Lv.4 이상 활성 길드도 즉시 반영하며, Lv.1~3 정원은 그대로 유지한다.
begin;

do $preflight$
declare
  v_target_guilds integer;
begin
  select count(*)::integer into v_target_guilds
  from public.gacha_s2_guilds
  where level >= 4 and disbanded_at is null;

  raise notice 'Guild Lv.4+ capacity targets: % active guild(s)', v_target_guilds;
end;
$preflight$;

alter table public.gacha_s2_guild_levels
  drop constraint if exists gacha_s2_guild_levels_member_limit_check;
alter table public.gacha_s2_guild_levels
  add constraint gacha_s2_guild_levels_member_limit_check
  check (member_limit between 1 and 60);

alter table public.gacha_s2_guilds
  drop constraint if exists gacha_s2_guilds_member_limit_check;
alter table public.gacha_s2_guilds
  add constraint gacha_s2_guilds_member_limit_check
  check (member_limit between 1 and 60);

update public.gacha_s2_guild_levels
set member_limit = 60
where level >= 4;

update public.gacha_s2_guilds
set member_limit = greatest(member_limit, 60),
    updated_at = now()
where level >= 4 and disbanded_at is null;

do $verify$
begin
  if exists (
    select 1
    from public.gacha_s2_guild_levels
    where level >= 4 and member_limit <> 60
  ) then
    raise exception 'Guild level 4+ capacity update failed';
  end if;

  if exists (
    select 1
    from public.gacha_s2_guilds
    where level >= 4 and disbanded_at is null and member_limit < 60
  ) then
    raise exception 'Existing guild capacity update failed';
  end if;
end;
$verify$;

commit;
