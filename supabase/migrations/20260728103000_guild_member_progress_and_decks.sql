-- 길드 주간 목표의 본인 기여도와 같은 길드원 덱 조회.
-- 두 조회 모두 service_role 전용이며, 길드 소속 관계를 서버에서 검증한다.

begin;

create or replace function public.gacha_s2_get_guild_weekly_member_progress(
  p_user_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_guild_id uuid;
  v_week date := public.gacha_s2_guild_week_start();
  v_members integer;
  v_goals jsonb := '[]'::jsonb;
  v_goal record;
  v_target integer;
  v_cap integer;
  v_actions bigint;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;

  select m.guild_id into v_guild_id
  from public.gacha_s2_guild_members m
  join public.gacha_s2_guilds g
    on g.guild_id = m.guild_id and g.disbanded_at is null
  where m.user_id = p_user_id;

  if v_guild_id is null then
    return jsonb_build_object('ok', true, 'weekStart', v_week, 'goals', '[]'::jsonb);
  end if;

  select count(*) into v_members
  from public.gacha_s2_guild_members
  where guild_id = v_guild_id;

  for v_goal in
    select * from (values
      ('adventure', '모험 클리어', 10),
      ('minigame', '미니게임 플레이', 7),
      ('worldboss', '월드보스 공격', 4)
    ) as g(key, label, per_member)
  loop
    v_target := ceil(v_goal.per_member::numeric * v_members)::integer;
    v_cap := greatest(1, ceil(v_target * 0.08)::integer);

    select coalesce(sum(c.actions), 0) into v_actions
    from public.gacha_s2_guild_contributions c
    where c.guild_id = v_guild_id
      and c.user_id = p_user_id
      and c.source = v_goal.key
      and c.day_kst >= v_week
      and c.day_kst < v_week + 7;

    v_goals := v_goals || jsonb_build_object(
      'key', v_goal.key,
      'actions', v_actions,
      'counted', least(v_actions, v_cap),
      'memberCap', v_cap,
      'complete', v_actions >= v_cap
    );
  end loop;

  return jsonb_build_object(
    'ok', true,
    'weekStart', v_week,
    'guildId', v_guild_id,
    'goals', v_goals
  );
end;
$$;

create or replace function public.gacha_s2_get_guild_member_profile(
  p_user_id uuid,
  p_target_user_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_guild_id uuid;
  v_profile jsonb;
begin
  if p_user_id is null or p_target_user_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'VALIDATION_FAILED',
      'message', '길드원 정보가 올바르지 않습니다.'
    );
  end if;

  select m.guild_id into v_guild_id
  from public.gacha_s2_guild_members m
  join public.gacha_s2_guilds g
    on g.guild_id = m.guild_id and g.disbanded_at is null
  where m.user_id = p_user_id;

  if v_guild_id is null or not exists (
    select 1
    from public.gacha_s2_guild_members target
    where target.guild_id = v_guild_id
      and target.user_id = p_target_user_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'code', 'FORBIDDEN',
      'message', '같은 길드원의 덱만 확인할 수 있습니다.'
    );
  end if;

  select jsonb_build_object(
    'ok', true,
    'userId', a.id,
    'nickname', a.nickname,
    'powerSnapshot', coalesce(s.power_snapshot, 0),
    'formation', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cardId', slot.card_id,
        'enhancement', coalesce(pc.enhancement, 0)
      ) order by slot.ord)
      from unnest(coalesce(s.formation, '{}'::text[]))
        with ordinality as slot(card_id, ord)
      join public.gacha_s2_player_cards pc
        on pc.user_id = s.user_id
       and pc.card_id = slot.card_id
       and pc.copies > 0
    ), '[]'::jsonb),
    'registeredCardIds', coalesce((
      select jsonb_agg(r.card_id order by r.card_id)
      from public.gacha_s2_collection_records r
      where r.user_id = s.user_id
    ), '[]'::jsonb),
    'guildBuff', public.gacha_s2_guild_buff(s.user_id)
  ) into v_profile
  from public.gacha_s2_accounts a
  join public.gacha_s2_player_states s on s.user_id = a.id
  where a.id = p_target_user_id;

  if v_profile is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'COMMAND_REJECTED',
      'message', '길드원 게임 정보를 찾을 수 없습니다.'
    );
  end if;

  return v_profile;
end;
$$;

revoke all on function public.gacha_s2_get_guild_weekly_member_progress(uuid)
  from public, anon, authenticated;
grant execute on function public.gacha_s2_get_guild_weekly_member_progress(uuid)
  to service_role;

revoke all on function public.gacha_s2_get_guild_member_profile(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.gacha_s2_get_guild_member_profile(uuid, uuid)
  to service_role;

commit;
