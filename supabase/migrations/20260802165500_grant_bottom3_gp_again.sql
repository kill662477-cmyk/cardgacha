-- 하위 3개 길드 인원에게 50 GP씩 다시 추가 지급 및 길드 GP 갱신

begin;

do $$
declare
  v_adjustment_prefix text := 'bottom3-bonus-50gp-20260802-v2-';
  v_guild_row record;
  v_member record;
  v_inserted text;
  v_award integer := 50;
  v_total_awarded integer := 0;
begin
  -- 하위 3개 활성 길드 순회
  for v_guild_row in (
    select guild_id, name
    from public.gacha_s2_guilds
    where disbanded_at is null
    order by total_gp asc
    limit 3
  )
  loop
    v_total_awarded := 0;

    -- 해당 길드의 모든 멤버 순회
    for v_member in (select user_id from public.gacha_s2_guild_members where guild_id = v_guild_row.guild_id)
    loop
      v_inserted := null;
      insert into public.gacha_s2_guild_gp_adjustments (
        adjustment_key, user_id, guild_id, nickname, source, gp_granted, actions_granted
      ) values (
        v_adjustment_prefix || v_guild_row.guild_id::text || '-' || v_member.user_id::text, 
        v_member.user_id, 
        v_guild_row.guild_id, 
        'SYSTEM', 
        'donation', 
        v_award, 
        1
      )
      on conflict (adjustment_key) do nothing
      returning adjustment_key into v_inserted;

      if v_inserted is not null then
        insert into public.gacha_s2_guild_contributions (
          guild_id, user_id, day_kst, source, gp, actions
        ) values (
          v_guild_row.guild_id, v_member.user_id, (now() at time zone 'Asia/Seoul')::date, 'donation', v_award, 1
        )
        on conflict (guild_id, user_id, day_kst, source) do update
        set gp = public.gacha_s2_guild_contributions.gp + excluded.gp,
            actions = public.gacha_s2_guild_contributions.actions + excluded.actions,
            updated_at = now();

        update public.gacha_s2_guild_members
        set weekly_gp = weekly_gp + v_award,
            total_gp = total_gp + v_award,
            last_contributed_at = now()
        where guild_id = v_guild_row.guild_id and user_id = v_member.user_id;

        v_total_awarded := v_total_awarded + v_award;
      end if;
    end loop;

    -- 길드 전체 GP 업데이트 및 레벨 갱신
    if v_total_awarded > 0 then
      update public.gacha_s2_guilds
      set total_gp = total_gp + v_total_awarded
      where guild_id = v_guild_row.guild_id;

      perform public.gacha_s2_guild_refresh_level(v_guild_row.guild_id);
    end if;
  end loop;

end;
$$;

commit;
