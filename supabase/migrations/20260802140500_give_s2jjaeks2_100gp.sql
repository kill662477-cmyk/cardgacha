-- S2 짹 S2 길드원 100 GP 지급

begin;

create table if not exists public.gacha_s2_guild_gp_adjustments (
  adjustment_key text primary key,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete restrict,
  guild_id uuid not null references public.gacha_s2_guilds(guild_id) on delete restrict,
  nickname text not null,
  source text not null,
  gp_granted integer not null check (gp_granted >= 0),
  actions_granted integer not null check (actions_granted > 0),
  created_at timestamptz not null default now()
);

do $$
declare
  v_adjustment_prefix text := 's2jjaeks2-bonus-100gp-20260802-';
  v_guild_id uuid;
  v_member record;
  v_inserted text;
  v_award integer := 100;
  v_total_awarded integer := 0;
begin
  select guild_id into v_guild_id
  from public.gacha_s2_guilds
  where btrim(name) = 'S2 짹 S2'
  limit 1;

  if v_guild_id is null then
    raise exception 'Guild S2 짹 S2 not found';
  end if;

  for v_member in (select user_id from public.gacha_s2_guild_members where guild_id = v_guild_id)
  loop
    v_inserted := null;
    insert into public.gacha_s2_guild_gp_adjustments (
      adjustment_key, user_id, guild_id, nickname, source, gp_granted, actions_granted
    ) values (
      v_adjustment_prefix || v_member.user_id::text, v_member.user_id, v_guild_id, 'SYSTEM', 'reward', v_award, 1
    )
    on conflict (adjustment_key) do nothing
    returning adjustment_key into v_inserted;

    if v_inserted is not null then
      insert into public.gacha_s2_guild_contributions (
        guild_id, user_id, day_kst, source, gp, actions
      ) values (
        v_guild_id, v_member.user_id, (now() at time zone 'Asia/Seoul')::date, 'reward', v_award, 1
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
end;
$$;

commit;
