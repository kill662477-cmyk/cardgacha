-- Let guild owners and officers inspect a pending applicant's current formation.
-- The profile is fetched lazily and is only returned while the join request is pending.

begin;

create or replace function public.gacha_s2_get_guild_applicant_profile(
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
      'message', '신청자 정보가 올바르지 않습니다.'
    );
  end if;

  select m.guild_id into v_guild_id
  from public.gacha_s2_guild_members m
  join public.gacha_s2_guilds g
    on g.guild_id = m.guild_id and g.disbanded_at is null
  where m.user_id = p_user_id
    and m.role in ('owner', 'officer');

  if v_guild_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'FORBIDDEN',
      'message', '가입 신청자를 확인할 권한이 없습니다.'
    );
  end if;

  if not exists (
    select 1
    from public.gacha_s2_guild_join_requests r
    where r.guild_id = v_guild_id
      and r.user_id = p_target_user_id
      and r.status = 'pending'
  ) then
    return jsonb_build_object(
      'ok', false,
      'code', 'COMMAND_REJECTED',
      'message', '대기 중인 가입 신청자가 아닙니다.'
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
      'message', '신청자 게임 정보를 찾을 수 없습니다.'
    );
  end if;

  return v_profile;
end;
$$;

revoke all on function public.gacha_s2_get_guild_applicant_profile(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.gacha_s2_get_guild_applicant_profile(uuid, uuid)
  to service_role;

commit;
