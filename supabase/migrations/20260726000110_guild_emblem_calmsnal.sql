-- 커스텀 길드 엠블럼 'calmsnal'(캄스날) 등록 및 적용.
--
-- 이미지: assets/renewal/guild/emblems/calmsnal.png (256x256 원형 마스크, 31KB)
-- 다른 커스텀 엠블럼과 달리 인물 사진이 아니라 문장(crest)이라, 방패·대포·연꽃·배너가
-- 모두 들어오도록 도안 전체를 잡았다. 원형 마스크 때문에 사각 테두리 모서리만 잘린다.
--
-- 방식은 20260725000107_guild_emblem_ilsin.sql 과 동일하다.
-- active = false 라 다른 길드 선택 목록에는 뜨지 않고, 화면 표시는 길드 행의 emblem 키를
-- 직접 읽으므로 정상 동작한다.
--
-- 주의: 길드장이 엠블럼을 다른 것으로 바꾸면 UI 로는 되돌릴 수 없다.
-- 복구하려면 아래 update 문을 다시 실행해야 한다.

insert into public.gacha_s2_guild_emblems (emblem_key, label, sort_order, active)
values ('calmsnal', '캄스날', 904, false)
on conflict (emblem_key) do update
  set label = excluded.label, sort_order = excluded.sort_order, active = excluded.active;

update public.gacha_s2_guilds
set emblem = 'calmsnal', updated_at = now()
where name = '캄스날' and disbanded_at is null;

do $$
declare v_count integer;
begin
  select count(*) into v_count
  from public.gacha_s2_guilds
  where name = '캄스날' and disbanded_at is null and emblem = 'calmsnal';
  if v_count <> 1 then
    raise exception 'calmsnal emblem not applied (matched % guilds)', v_count;
  end if;
end;
$$;
