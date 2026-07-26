insert into public.gacha_s2_guild_emblems (emblem_key, label, sort_order, active)
values ('ilsin', '유일신', 900, false)
on conflict (emblem_key) do update
  set label = excluded.label, sort_order = excluded.sort_order, active = excluded.active;

update public.gacha_s2_guilds
set emblem = 'ilsin', updated_at = now()
where name = '유일신의 신도들' and disbanded_at is null;

do $$
declare v_count integer;
begin
  select count(*) into v_count
  from public.gacha_s2_guilds
  where name = '유일신의 신도들' and disbanded_at is null and emblem = 'ilsin';
  if v_count <> 1 then
    raise exception 'ilsin emblem not applied (matched % guilds)', v_count;
  end if;
end;
$$;;
