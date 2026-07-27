-- 찌킹단 / 섹시테란 커스텀 이미지 엠블럼 등록(PDB-16 7.2).
-- active=false 라 엠블럼 선택 목록에는 뜨지 않고, 해당 길드에만 고정으로 붙는다.
insert into public.gacha_s2_guild_emblems (emblem_key, label, sort_order, active)
values ('jjiking', '찌킹단', 905, false),
       ('sexyterran', '섹시테란', 906, false)
on conflict (emblem_key) do update
  set label = excluded.label, sort_order = excluded.sort_order, active = excluded.active;

update public.gacha_s2_guilds
set emblem = 'jjiking', updated_at = now()
where name = '찌킹단' and disbanded_at is null;

update public.gacha_s2_guilds
set emblem = 'sexyterran', updated_at = now()
where name = '섹시테란' and disbanded_at is null;

do $$
declare v_count integer;
begin
  select count(*) into v_count
  from public.gacha_s2_guilds
  where disbanded_at is null
    and ((name = '찌킹단' and emblem = 'jjiking') or (name = '섹시테란' and emblem = 'sexyterran'));
  if v_count <> 2 then
    raise exception 'jjiking/sexyterran emblem not applied (matched % guilds)', v_count;
  end if;
end;
$$;
