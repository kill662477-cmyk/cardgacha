-- 빠른전투도 일반 모험 완료와 동일하게 길드 GP와 주간 모험 목표에 반영한다.
create or replace function public.gacha_s2_guild_gp_from_command()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_gp integer;
  v_source text;
  v_guild_id uuid;
  v_day date;
  v_today integer;
  v_cap constant integer := 200;
  v_award integer;
begin
  case new.command_type
    when 'finishAdventureRun' then v_gp := 5;  v_source := 'adventure';
    when 'claimQuickBattle'    then v_gp := 5;  v_source := 'adventure';
    when 'finishMinigame'      then v_gp := 2;  v_source := 'minigame';
    when 'playLadder'          then v_gp := 2;  v_source := 'minigame';
    when 'attackWorldBoss'     then v_gp := 10; v_source := 'worldboss';
    when 'attackGuildRaid'     then v_gp := 15; v_source := 'raid';
    else return new;
  end case;

  select m.guild_id into v_guild_id
  from public.gacha_s2_guild_members m
  join public.gacha_s2_guilds g on g.guild_id = m.guild_id
  where m.user_id = new.user_id and g.disbanded_at is null;
  if v_guild_id is null then return new; end if;

  v_day := (now() at time zone 'Asia/Seoul')::date;

  select coalesce(sum(gp), 0) into v_today
  from public.gacha_s2_guild_contributions
  where user_id = new.user_id and day_kst = v_day;
  v_award := greatest(0, least(v_gp, v_cap - v_today));

  insert into public.gacha_s2_guild_contributions (guild_id, user_id, day_kst, source, gp, actions)
  values (v_guild_id, new.user_id, v_day, v_source, v_award, 1)
  on conflict (guild_id, user_id, day_kst, source) do update
  set gp = public.gacha_s2_guild_contributions.gp + excluded.gp,
      actions = public.gacha_s2_guild_contributions.actions + 1,
      updated_at = now();

  if v_award > 0 then
    update public.gacha_s2_guild_members
    set weekly_gp = weekly_gp + v_award,
        total_gp = total_gp + v_award,
        last_contributed_at = now()
    where guild_id = v_guild_id and user_id = new.user_id;

    update public.gacha_s2_guilds
    set total_gp = total_gp + v_award
    where guild_id = v_guild_id;

    perform public.gacha_s2_guild_refresh_level(v_guild_id);
  else
    update public.gacha_s2_guild_members
    set last_contributed_at = now()
    where guild_id = v_guild_id and user_id = new.user_id;
  end if;

  return new;
end;
$$;
