create or replace function public.gacha_s2_open_guild_raids(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_slot timestamptz;
  v_guild record;
  v_opened integer := 0;
begin
  v_slot := public.gacha_s2_guild_raid_current_slot(p_now);
  if v_slot is null then return 0; end if;

  for v_guild in
    select guild_id from public.gacha_s2_guilds where disbanded_at is null
  loop
    perform public.gacha_s2_ensure_guild_raid(v_guild.guild_id, p_now);
    v_opened := v_opened + 1;
  end loop;

  return v_opened;
end;
$$;

revoke all on function public.gacha_s2_open_guild_raids(timestamptz) from public, anon, authenticated;

create or replace function public.gacha_s2_get_guild_raid_status(p_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_guild_id uuid;
  v_raid public.gacha_s2_guild_raids%rowtype;
  v_now timestamptz := now();
  v_slot timestamptz;
begin
  select gm.guild_id into v_guild_id from public.gacha_s2_guild_membership(p_user_id) gm;
  if v_guild_id is null then return jsonb_build_object('active', false, 'raid', null); end if;

  v_slot := public.gacha_s2_guild_raid_current_slot(v_now);
  if v_slot is not null then
    perform public.gacha_s2_ensure_guild_raid(v_guild_id, v_now);
  end if;

  select * into v_raid from public.gacha_s2_guild_raids
  where guild_id = v_guild_id and (v_slot is null or starts_at = v_slot)
  order by starts_at desc limit 1;

  if v_raid.raid_id is null then
    return jsonb_build_object('active', false, 'raid', null, 'nextSlot', null);
  end if;

  return jsonb_build_object(
    'active', v_now >= v_raid.starts_at and v_now < v_raid.raid_ends_at and v_raid.current_hp > 0,
    'resultsOpen', v_now >= v_raid.raid_ends_at and v_now < v_raid.ends_at,
    'raid', jsonb_build_object(
      'raidId', v_raid.raid_id,
      'startsAt', floor(extract(epoch from v_raid.starts_at) * 1000)::bigint,
      'raidEndsAt', floor(extract(epoch from v_raid.raid_ends_at) * 1000)::bigint,
      'endsAt', floor(extract(epoch from v_raid.ends_at) * 1000)::bigint,
      'maxHp', v_raid.max_hp,
      'currentHp', v_raid.current_hp,
      'playerDamage', v_raid.player_damage,
      'activeMemberCount', v_raid.active_member_count,
      'defeated', v_raid.current_hp = 0
    ),
    'me', (
      select jsonb_build_object('attempts', p.attempts, 'totalDamage', p.total_damage,
        'claimed', p.claimed_at is not null, 'rewardPoints', p.reward_points)
      from public.gacha_s2_guild_raid_players p
      where p.raid_id = v_raid.raid_id and p.user_id = p_user_id
    ),
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', p.user_id, 'nickname', a.nickname,
        'attempts', p.attempts, 'totalDamage', p.total_damage,
        'claimed', p.claimed_at is not null
      ) order by p.total_damage desc, a.nickname)
      from public.gacha_s2_guild_raid_players p
      join public.gacha_s2_accounts a on a.id = p.user_id
      where p.raid_id = v_raid.raid_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.gacha_s2_get_guild_raid_status(uuid) from public, anon, authenticated;
grant execute on function public.gacha_s2_get_guild_raid_status(uuid) to service_role;;
