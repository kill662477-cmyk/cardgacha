-- 커스텀 길드 엠블럼 'chiri' 등록 + '검투사' 길드에 적용.
--
-- 이미지: assets/renewal/guild/emblems/chiri.png (256x256 원형 마스크, 24KB)
-- 렌더링/비노출 방식은 20260725000107_guild_emblem_ilsin.sql 과 동일하다.
-- active = false 라 선택 목록에 뜨지 않고, 화면 표시는 길드 행의 emblem 키를 직접 읽어 정상 동작한다.
--
-- 주의: 이 길드의 길드장이 엠블럼을 다른 것으로 바꾸면 UI 로는 되돌릴 수 없다.
-- 복구하려면 아래 update 문을 다시 실행해야 한다.

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
$$;
