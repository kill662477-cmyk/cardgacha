-- 커스텀 길드 엠블럼 'byungdan'(븅단폭격) / 'harang'(하랑단) 등록 및 적용.
--
-- 이미지: assets/renewal/guild/emblems/{byungdan,harang}.png (256x256 원형 마스크, 각 29KB)
-- 방식은 20260725000107_guild_emblem_ilsin.sql 과 동일하다.
-- active = false 라 다른 길드 선택 목록에는 뜨지 않고, 화면 표시는 길드 행의 emblem 키를
-- 직접 읽으므로 정상 동작한다.
--
-- 이로써 현재 활동 중인 길드 4곳이 모두 전용 엠블럼을 갖는다.
--
-- 주의: 길드장이 엠블럼을 다른 것으로 바꾸면 UI 로는 되돌릴 수 없다.
-- 복구하려면 해당 update 문을 다시 실행해야 한다.

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
$$;
