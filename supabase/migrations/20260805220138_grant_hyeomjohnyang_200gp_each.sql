-- 혐좋냥 길드원 전원에게 200 GP 씩 지급.
-- adjustment_key 로 멱등성을 잡아 재실행해도 중복 지급되지 않는다.
-- 개인 기여도(weekly_gp/total_gp)와 길드 총 GP 를 함께 올리고 레벨을 재계산한다.
do $$
declare
  v_guild_id uuid;
  v_key_prefix text := 'hyeomjohnyang-200gp-20260805-';
  v_member record;
  v_inserted text;
  v_award integer := 200;
  v_total_awarded integer := 0;
  v_members integer := 0;
begin
  select guild_id into v_guild_id
  from public.gacha_s2_guilds
  where name = '혐좋냥' and disbanded_at is null;
  if v_guild_id is null then
    raise exception 'guild 혐좋냥 not found';
  end if;

  for v_member in (select user_id from public.gacha_s2_guild_members where guild_id = v_guild_id)
  loop
    v_members := v_members + 1;
    v_inserted := null;
    insert into public.gacha_s2_guild_gp_adjustments (
      adjustment_key, user_id, guild_id, nickname, source, gp_granted, actions_granted
    ) values (
      v_key_prefix || v_member.user_id::text,
      v_member.user_id, v_guild_id, 'SYSTEM', 'donation', v_award, 1
    )
    on conflict (adjustment_key) do nothing
    returning adjustment_key into v_inserted;

    if v_inserted is not null then
      insert into public.gacha_s2_guild_contributions (
        guild_id, user_id, day_kst, source, gp, actions
      ) values (
        v_guild_id, v_member.user_id, (now() at time zone 'Asia/Seoul')::date, 'donation', v_award, 1
      )
      on conflict (guild_id, user_id, day_kst, source) do update
      set gp = public.gacha_s2_guild_contributions.gp + excluded.gp,
          actions = public.gacha_s2_guild_contributions.actions + excluded.actions,
          updated_at = now();

      update public.gacha_s2_guild_members
      set weekly_gp = weekly_gp + v_award,
          total_gp = total_gp + v_award,
          last_contributed_at = now()
      where guild_id = v_guild_id and user_id = v_member.user_id;

      v_total_awarded := v_total_awarded + v_award;
    end if;
  end loop;

  if v_total_awarded > 0 then
    update public.gacha_s2_guilds
    set total_gp = total_gp + v_total_awarded
    where guild_id = v_guild_id;
    perform public.gacha_s2_guild_refresh_level(v_guild_id);
  end if;

  if v_total_awarded <> v_members * v_award then
    raise exception 'grant coverage mismatch: awarded % vs expected %', v_total_awarded, v_members * v_award;
  end if;
end;
$$;
