-- 길드 레이드 난이도 50% 하향: 활동 길드원 1인당 HP 6,300만 -> 3,150만.
-- 08-05 21:00 회차에서 9개 길드 전부 실패했다. 최고 진행도가 유일신의 신도들 72.8%
-- (31.6억 / 43.5억), 나머지는 22~55% 였다. 절반으로 내리면 오늘 딜 기준 전부 격파 가능하다.
--
-- 08-01 회차는 인당 2,100만이었고 참여 길드가 모두 격파했다. 이번 값(3,150만)은
-- 그 사이 지점이라 성장분을 반영하면서도 다수 참여 전제를 유지한다.
--
-- 예정된 레이드 행은 없다(다음 회차는 토요일 21:00 에 이 함수로 생성된다).
-- 진행이 끝난 기존 행은 건드리지 않는다.
create or replace function public.gacha_s2_ensure_guild_raid(p_guild_id uuid, p_now timestamp with time zone default now())
returns gacha_s2_guild_raids
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
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

  -- 2026-08-05: 6,300만 -> 3,150만 (난이도 50% 하향).
  v_hp := greatest(v_active, 1)::bigint * 31500000;

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
$function$;

do $$
declare
  v_src text;
  v_pending integer;
begin
  v_src := pg_get_functiondef('public.gacha_s2_ensure_guild_raid(uuid,timestamptz)'::regprocedure);
  if v_src not like '%31500000%' then
    raise exception 'guild raid HP not halved';
  end if;
  if v_src like '%63000000%' then
    raise exception 'old guild raid HP literal still present';
  end if;

  -- 예정 회차가 남아 있으면 옛 HP 로 생성된 행이 있다는 뜻이라 별도 보정이 필요하다.
  select count(*) into v_pending from public.gacha_s2_guild_raids where starts_at > now();
  if v_pending > 0 then
    raise exception 'pending guild raids exist and would keep the old HP: %', v_pending;
  end if;
end;
$$;
