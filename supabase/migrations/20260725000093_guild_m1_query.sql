-- 길드 M1 조회 RPC (PDB-16)
--
-- 기존 gacha_s2_get_player_snapshot 은 수정하지 않는다. 월드보스 상태(getWorldBossStatus)와
-- 동일하게 길드도 별도 조회 RPC로 분리해, 핵심 스냅샷 경로에 회귀 위험을 만들지 않는다.

-- 유저의 현재 소속을 조회하는 내부 헬퍼.
create or replace function public.gacha_s2_guild_membership(p_user_id uuid)
returns table (guild_id uuid, role text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select m.guild_id, m.role
  from public.gacha_s2_guild_members m
  join public.gacha_s2_guilds g on g.guild_id = m.guild_id
  where m.user_id = p_user_id and g.disbanded_at is null;
$$;

-- 길드 공개 정보 + 멤버 목록 + (권한자에 한해) 가입 신청 목록.
-- 멤버 목록은 길드원 전원에게 공개한다(PDB-16 2.6 기여도 가시성).
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

  -- 조회 대상: 인자로 받은 길드가 우선, 없으면 본인 소속 길드.
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
    -- 소속도 없고 지정한 길드도 없으면 길드 목록만 돌려준다.
    return jsonb_build_object(
      'ok', true,
      'membership', null,
      'penaltyUntil', case when v_penalty is null then null
        else floor(extract(epoch from v_penalty) * 1000)::bigint end,
      'guild', null,
      'guilds', public.gacha_s2_list_guilds()
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
    -- 멤버 목록: 기여도 판단 근거를 길드원 전원에게 공개한다.
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
    -- 가입 신청 목록은 승인 권한자에게만 노출한다.
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
    -- 본인이 보낸 대기 중 신청(다른 길드 포함).
    'myRequests', coalesce((
      select jsonb_agg(jsonb_build_object('guildId', r.guild_id, 'name', g.name))
      from public.gacha_s2_guild_join_requests r
      join public.gacha_s2_guilds g on g.guild_id = r.guild_id
      where r.user_id = p_user_id and r.status = 'pending' and g.disbanded_at is null
    ), '[]'::jsonb)
  );
end;
$$;

-- 가입 가능한 길드 목록. 인원이 찬 길드도 보이되 memberCount 로 판단하게 한다.
create or replace function public.gacha_s2_list_guilds()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(entry order by entry->>'name'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'guildId', g.guild_id,
      'name', g.name,
      'tag', g.tag,
      'emblem', g.emblem,
      'level', g.level,
      'joinMode', g.join_mode,
      'memberLimit', g.member_limit,
      'ownerNickname', a.nickname,
      'memberCount', (
        select count(*) from public.gacha_s2_guild_members m where m.guild_id = g.guild_id
      )
    ) as entry
    from public.gacha_s2_guilds g
    join public.gacha_s2_accounts a on a.id = g.owner_user_id
    where g.disbanded_at is null
  ) rows;
$$;

-- 선택 가능한 엠블럼 목록.
create or replace function public.gacha_s2_list_guild_emblems()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', emblem_key, 'label', label) order by sort_order), '[]'::jsonb)
  from public.gacha_s2_guild_emblems
  where active;
$$;

revoke all on function public.gacha_s2_guild_membership(uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_get_guild_state(uuid, uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_list_guilds() from public, anon, authenticated;
revoke all on function public.gacha_s2_list_guild_emblems() from public, anon, authenticated;

grant execute on function public.gacha_s2_guild_membership(uuid) to service_role;
grant execute on function public.gacha_s2_get_guild_state(uuid, uuid) to service_role;
grant execute on function public.gacha_s2_list_guilds() to service_role;
grant execute on function public.gacha_s2_list_guild_emblems() to service_role;
