-- 길드 목록에 누적 GP를 포함하고 GP 내림차순으로 반환한다.
begin;

create or replace function public.gacha_s2_list_guilds()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'guildId', g.guild_id,
      'name', g.name,
      'tag', g.tag,
      'emblem', g.emblem,
      'level', g.level,
      'totalGp', g.total_gp,
      'joinMode', g.join_mode,
      'memberLimit', g.member_limit,
      'ownerNickname', a.nickname,
      'memberCount', (
        select count(*)
        from public.gacha_s2_guild_members m
        where m.guild_id = g.guild_id
      )
    ) order by g.total_gp desc, lower(g.name), g.guild_id
  ), '[]'::jsonb)
  from public.gacha_s2_guilds g
  join public.gacha_s2_accounts a on a.id = g.owner_user_id
  where g.disbanded_at is null;
$$;

revoke all on function public.gacha_s2_list_guilds()
  from public, anon, authenticated;
grant execute on function public.gacha_s2_list_guilds() to service_role;

commit;
