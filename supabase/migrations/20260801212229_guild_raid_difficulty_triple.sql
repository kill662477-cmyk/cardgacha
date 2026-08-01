-- Triple future guild-raid HP from 21,000,000 to 63,000,000 per active member.
-- Existing raids are intentionally preserved so completed results and claims do not change.

begin;

create or replace function public.gacha_s2_ensure_guild_raid(
  p_guild_id uuid,
  p_now timestamptz default now()
) returns public.gacha_s2_guild_raids
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_slot timestamptz;
  v_raid public.gacha_s2_guild_raids%rowtype;
  v_active integer;
  v_hp bigint;
begin
  v_slot := public.gacha_s2_guild_raid_current_slot(p_now);
  if v_slot is null then return null; end if;

  select * into v_raid from public.gacha_s2_guild_raids
  where guild_id = p_guild_id and starts_at = v_slot;
  if found then return v_raid; end if;

  -- Do not create an empty raid during the result window.
  if p_now >= v_slot + interval '30 minutes' then
    return null;
  end if;

  select count(*) into v_active
  from public.gacha_s2_guild_members
  where guild_id = p_guild_id
    and last_contributed_at is not null
    and last_contributed_at >= p_now - interval '7 days';

  v_hp := greatest(v_active, 1)::bigint * 63000000;

  insert into public.gacha_s2_guild_raids (
    guild_id, starts_at, raid_ends_at, ends_at, active_member_count, max_hp, current_hp
  ) values (
    p_guild_id, v_slot, v_slot + interval '30 minutes', v_slot + interval '1 hour',
    v_active, v_hp, v_hp
  )
  on conflict (guild_id, starts_at) do nothing
  returning * into v_raid;

  if v_raid.raid_id is null then
    select * into v_raid from public.gacha_s2_guild_raids
    where guild_id = p_guild_id and starts_at = v_slot;
    return v_raid;
  end if;

  insert into public.gacha_s2_guild_raid_players (raid_id, user_id)
  select v_raid.raid_id, member.user_id
  from public.gacha_s2_guild_members member
  where member.guild_id = p_guild_id
  on conflict do nothing;

  return v_raid;
end;
$$;

revoke all on function public.gacha_s2_ensure_guild_raid(uuid, timestamptz)
from public, anon, authenticated;

do $verify$
declare
  v_function text;
begin
  select pg_get_functiondef(
    'public.gacha_s2_ensure_guild_raid(uuid,timestamptz)'::regprocedure
  ) into v_function;

  if v_function not like '%greatest(v_active, 1)::bigint * 63000000%' then
    raise exception 'Guild raid HP multiplier verification failed';
  end if;
end;
$verify$;

commit;
