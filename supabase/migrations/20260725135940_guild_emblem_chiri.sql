insert into public.gacha_s2_guild_emblems (emblem_key, label, sort_order, active)
values ('chiri', '치리', 901, false)
on conflict (emblem_key) do update
  set label = excluded.label, sort_order = excluded.sort_order, active = excluded.active;

update public.gacha_s2_guilds
set emblem = 'chiri', updated_at = now()
where name = '검투사' and disbanded_at is null;

do $$
declare v_count integer;
begin
  select count(*) into v_count
  from public.gacha_s2_guilds
  where name = '검투사' and disbanded_at is null and emblem = 'chiri';
  if v_count <> 1 then
    raise exception 'chiri emblem not applied (matched % guilds)', v_count;
  end if;
end;
$$;;
