begin;

insert into public.gacha_s2_guild_emblems (emblem_key, label, sort_order, active)
values ('s2jjaek', 'S2 짹 S2 전용', 907, false)
on conflict (emblem_key) do update
  set label = excluded.label,
      sort_order = excluded.sort_order,
      active = excluded.active;

do $apply$
declare
  v_count integer;
begin
  update public.gacha_s2_guilds
  set emblem = 's2jjaek', updated_at = now()
  where guild_id = 'bea1d9dc-48cc-4a33-b80d-243d59d069d4'::uuid
    and name = 'S2 짹 S2'
    and disbanded_at is null;

  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'S2 짹 S2 emblem not applied (matched % guilds)', v_count;
  end if;
end;
$apply$;

commit;
