-- 2026-07-28 17시 월드보스가 예정된 75억이 아닌 65억으로 열린 운영 실수 보상.
-- 원인은 20260728171000_worldboss_resync_pending_hp.sql 주석 참고
-- (회차가 미리 생성된 뒤 설정을 바꿔 옛 값이 남았다).
--
-- 지급: 전 계정 30,000 P(개별 우편) + 길드 가입자 GP 30(월드보스 1회차 3회 공격분).
insert into public.gacha_s2_mailbox (user_id, event_key, category, title, body, points)
select a.id,
       'worldboss-hp-misconfig-20260728',
       'REWARD',
       '[보상] 월드보스 17시 체력 설정 오류 안내 · 30,000 P 지급',
       E'오늘(7월 28일) 17시 월드보스가 예정된 75억이 아닌 65억 체력으로 열렸습니다.\n\n'
       'ㅤ\n'
       '7월 27일 저녁에 체력을 17시 75억 / 18시 85억 / 19시 92억 / 20시 98억으로 상향했으나, '
       '17시 회차는 그 이전에 이미 옛 설정값으로 생성되어 있었습니다. 이를 확인하지 못한 운영 실수입니다.\n\n'
       '그 결과 17시 보스가 약 1분 만에 처치되어 많은 분들이 공격 기회를 사용하지 못했습니다.\n\n'
       'ㅤ\n'
       '[보상]\n'
       '· 전 계정 30,000 P\n'
       '· 길드 가입자 추가로 공헌도(GP) 30 지급 (월드보스 1회차 3회 공격분)\n\n'
       'ㅤ\n'
       '18시 이후 회차는 정상 수치로 진행됩니다. 재발 방지를 위해 아직 시작하지 않은 회차의 체력을 '
       '현재 설정값과 자동으로 대조·보정하는 절차를 추가했습니다.\n\n'
       '불편을 드려 죄송합니다.',
       30000
from public.gacha_s2_accounts a
on conflict (user_id, event_key) do nothing;

-- 보상 GP 는 일일 상한(200)을 적용하지 않는다. 상한은 소수 인원이 길드 레벨을 독주하지
-- 못하게 막는 장치이지, 운영 실수 보상을 깎기 위한 값이 아니다. 상한을 넘게 되는 인원은 2명.
with targets as (
  select m.user_id, m.guild_id, coalesce(a.nickname, '(unknown)') as nickname
  from public.gacha_s2_guild_members m
  join public.gacha_s2_guilds g using (guild_id)
  join public.gacha_s2_accounts a on a.id = m.user_id
  where g.disbanded_at is null
), ins_adj as (
  insert into public.gacha_s2_guild_gp_adjustments
    (adjustment_key, user_id, guild_id, nickname, source, gp_granted, actions_granted)
  select 'worldboss-hp-misconfig-20260728:' || t.user_id, t.user_id, t.guild_id, t.nickname, 'worldboss', 30, 3
  from targets t
  on conflict (adjustment_key) do nothing
  returning user_id, guild_id
), ins_contrib as (
  insert into public.gacha_s2_guild_contributions (guild_id, user_id, day_kst, source, gp, actions)
  select i.guild_id, i.user_id, (now() at time zone 'Asia/Seoul')::date, 'worldboss', 30, 3
  from ins_adj i
  on conflict (guild_id, user_id, day_kst, source) do update
  set gp = public.gacha_s2_guild_contributions.gp + excluded.gp,
      actions = public.gacha_s2_guild_contributions.actions + excluded.actions,
      updated_at = now()
  returning user_id
), upd_member as (
  update public.gacha_s2_guild_members m
  set weekly_gp = m.weekly_gp + 30, total_gp = m.total_gp + 30, last_contributed_at = now()
  from ins_adj i where m.user_id = i.user_id and m.guild_id = i.guild_id
  returning m.guild_id
)
update public.gacha_s2_guilds g
set total_gp = g.total_gp + s.cnt * 30
from (select guild_id, count(*) as cnt from ins_adj group by guild_id) s
where g.guild_id = s.guild_id;

do $$
declare v_guild_id uuid;
begin
  for v_guild_id in select guild_id from public.gacha_s2_guilds where disbanded_at is null loop
    perform public.gacha_s2_guild_refresh_level(v_guild_id);
  end loop;
end;
$$;
