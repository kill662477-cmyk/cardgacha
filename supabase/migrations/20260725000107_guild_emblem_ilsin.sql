-- 커스텀 길드 엠블럼 'ilsin' 등록 + '유일신의 신도들' 길드에 적용.
--
-- 이미지: assets/renewal/guild/emblems/ilsin.png (256x256 원형 마스크, 27KB)
-- 렌더링: src/renewal/guild-emblem.js 의 EMBLEM_IMAGES 에 키가 있으면 이모지 대신 이미지를 쓴다.
--
-- active = false 로 넣는 이유:
--   * 엠블럼 선택 목록(gacha_s2_get_guild_state)과 변경 검증(update_guild_settings /
--     create_guild)은 모두 active = true 인 키만 허용한다.
--   * 실존 인물 사진이라 다른 길드가 골라 쓰게 두지 않는다.
--   * 화면 렌더링은 길드 행의 emblem 키를 그대로 읽으므로 active 여부와 무관하게 표시된다.
--
-- 주의: 이 길드의 길드장이 설정에서 엠블럼을 다른 것으로 바꾸면 active = false 라
-- UI 로는 되돌릴 수 없다. 복구하려면 아래 update 문을 다시 실행해야 한다.

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
$$;
