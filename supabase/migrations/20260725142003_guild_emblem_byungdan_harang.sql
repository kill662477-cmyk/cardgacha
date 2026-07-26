insert into public.gacha_s2_guild_emblems (emblem_key, label, sort_order, active)
values
  ('byungdan', '븅단폭격', 902, false),
  ('harang',   '하랑단',   903, false)
on conflict (emblem_key) do update
  set label = excluded.label, sort_order = excluded.sort_order, active = excluded.active;

update public.gacha_s2_guilds
set emblem = 'byungdan', updated_at = now()
where name = '븅단폭격' and disbanded_at is null;

update public.gacha_s2_guilds
set emblem = 'harang', updated_at = now()
where name = '하랑단' and disbanded_at is null;

do $$
declare v_count integer;
begin
  select count(*) into v_count
  from public.gacha_s2_guilds
  where disbanded_at is null
    and ((name = '븅단폭격' and emblem = 'byungdan') or (name = '하랑단' and emblem = 'harang'));
  if v_count <> 2 then
    raise exception 'byungdan/harang emblems not applied (matched % guilds)', v_count;
  end if;
end;
$$;;
