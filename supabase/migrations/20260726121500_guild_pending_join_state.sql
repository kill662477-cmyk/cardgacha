-- Return the current user's pending join requests even when they do not belong
-- to a guild. The previous early-return branch omitted myRequests, so the
-- browser could not replace "가입 신청" with the pending/cancel controls.

begin;

create or replace function public.gacha_s2_get_guild_state(p_user_id uuid, p_guild_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_guild_id uuid;
  v_role text;
  v_guild public.gacha_s2_guilds%rowtype;
  v_is_member boolean := false;
  v_can_manage boolean := false;
  v_penalty timestamptz;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;

  select gm.guild_id, gm.role into v_guild_id, v_role
  from public.gacha_s2_guild_membership(p_user_id) gm;

  if p_guild_id is not null then
    select * into v_guild from public.gacha_s2_guilds
    where guild_id = p_guild_id and disbanded_at is null;
  elsif v_guild_id is not null then
    select * into v_guild from public.gacha_s2_guilds where guild_id = v_guild_id;
  end if;

  select penalty_until into v_penalty
  from public.gacha_s2_guild_leave_penalties
  where user_id = p_user_id and penalty_until > now();

  if v_guild.guild_id is null then
    return jsonb_build_object(
      'ok', true,
      'membership', null,
      'penaltyUntil', case when v_penalty is null then null
        else floor(extract(epoch from v_penalty) * 1000)::bigint end,
      'guild', null,
      'myRequests', coalesce((
        select jsonb_agg(jsonb_build_object(
          'guildId', r.guild_id,
          'name', g.name,
          'requestedAt', floor(extract(epoch from r.requested_at) * 1000)::bigint
        ) order by r.requested_at)
        from public.gacha_s2_guild_join_requests r
        join public.gacha_s2_guilds g on g.guild_id = r.guild_id
        where r.user_id = p_user_id
          and r.status = 'pending'
          and g.disbanded_at is null
      ), '[]'::jsonb),
      'guilds', public.gacha_s2_list_guilds(),
      'emblems', public.gacha_s2_list_guild_emblems(),
      'canCreateGuild', coalesce((
        select is_streamer from public.gacha_s2_accounts where id = p_user_id
      ), false),
      'weekly', null
    );
  end if;

  v_is_member := v_guild_id is not null and v_guild_id = v_guild.guild_id;
  v_can_manage := v_is_member and v_role in ('owner', 'officer');

  return jsonb_build_object(
    'ok', true,
    'membership', case when v_guild_id is null then null else jsonb_build_object(
      'guildId', v_guild_id, 'role', v_role
    ) end,
    'penaltyUntil', case when v_penalty is null then null
      else floor(extract(epoch from v_penalty) * 1000)::bigint end,
    'guild', jsonb_build_object(
      'guildId', v_guild.guild_id,
      'name', v_guild.name,
      'tag', v_guild.tag,
      'notice', v_guild.notice,
      'emblem', v_guild.emblem,
      'joinMode', v_guild.join_mode,
      'level', v_guild.level,
      'totalGp', v_guild.total_gp,
      'memberLimit', v_guild.member_limit,
      'ownerUserId', v_guild.owner_user_id,
      'createdAt', floor(extract(epoch from v_guild.created_at) * 1000)::bigint,
      'memberCount', (
        select count(*) from public.gacha_s2_guild_members where guild_id = v_guild.guild_id
      )
    ),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', m.user_id,
        'nickname', a.nickname,
        'role', m.role,
        'weeklyGp', m.weekly_gp,
        'totalGp', m.total_gp,
        'joinedAt', floor(extract(epoch from m.joined_at) * 1000)::bigint,
        'lastContributedAt', case when m.last_contributed_at is null then null
          else floor(extract(epoch from m.last_contributed_at) * 1000)::bigint end
      ) order by
        case m.role when 'owner' then 0 when 'officer' then 1 else 2 end,
        m.weekly_gp desc)
      from public.gacha_s2_guild_members m
      join public.gacha_s2_accounts a on a.id = m.user_id
      where m.guild_id = v_guild.guild_id
    ), '[]'::jsonb),
    'joinRequests', case when v_can_manage then coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', r.user_id,
        'nickname', a.nickname,
        'requestedAt', floor(extract(epoch from r.requested_at) * 1000)::bigint
      ) order by r.requested_at)
      from public.gacha_s2_guild_join_requests r
      join public.gacha_s2_accounts a on a.id = r.user_id
      where r.guild_id = v_guild.guild_id and r.status = 'pending'
    ), '[]'::jsonb) else null end,
    'myRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'guildId', r.guild_id,
        'name', g.name,
        'requestedAt', floor(extract(epoch from r.requested_at) * 1000)::bigint
      ) order by r.requested_at)
      from public.gacha_s2_guild_join_requests r
      join public.gacha_s2_guilds g on g.guild_id = r.guild_id
      where r.user_id = p_user_id
        and r.status = 'pending'
        and g.disbanded_at is null
    ), '[]'::jsonb),
    'guilds', public.gacha_s2_list_guilds(),
    'emblems', public.gacha_s2_list_guild_emblems(),
    'canCreateGuild', coalesce((
      select is_streamer from public.gacha_s2_accounts where id = p_user_id
    ), false),
    'weekly', case when v_is_member then
      public.gacha_s2_guild_weekly_progress(v_guild.guild_id)
      || jsonb_build_object('claimed', exists (
           select 1 from public.gacha_s2_guild_weekly_claims
           where guild_id = v_guild.guild_id
             and week_start_kst = public.gacha_s2_guild_week_start()
             and user_id = p_user_id))
      else null end
  );
end;
$$;

revoke all on function public.gacha_s2_get_guild_state(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.gacha_s2_get_guild_state(uuid, uuid) to service_role;

commit;
