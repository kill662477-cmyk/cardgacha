-- 혐좋냥 전용 길드마크 적용 + 2026-08-02 운영 요청에 따른 활성 길드 페널티 1회 해제.
-- 사전 읽기 전용 확인: 혐좋냥 활성 길드 1개, 활성 페널티 2명(leave 2, kick 0).
-- 페널티 이력은 삭제하지 않고 만료 시각만 현재 시각으로 당긴다.
begin;

insert into public.gacha_s2_guild_emblems (emblem_key, label, sort_order, active)
values ('hyeomjohnyang', '혐좋냥 전용', 908, false)
on conflict (emblem_key) do update
  set label = excluded.label,
      sort_order = excluded.sort_order,
      active = excluded.active;

do $apply$
declare
  v_guild_count integer;
  v_penalty_target integer;
  v_penalty_remaining integer;
begin
  update public.gacha_s2_guilds
  set emblem = 'hyeomjohnyang', updated_at = now()
  where name = '혐좋냥'
    and disbanded_at is null;

  get diagnostics v_guild_count = row_count;
  if v_guild_count <> 1 then
    raise exception '혐좋냥 emblem not applied (matched % guilds)', v_guild_count;
  end if;

  select count(*) into v_penalty_target
  from public.gacha_s2_guild_leave_penalties
  where penalty_until > now();

  update public.gacha_s2_guild_leave_penalties
  set penalty_until = now()
  where penalty_until > now();

  select count(*) into v_penalty_remaining
  from public.gacha_s2_guild_leave_penalties
  where penalty_until > now();

  if v_penalty_remaining <> 0 then
    raise exception 'guild leave penalties still active: %', v_penalty_remaining;
  end if;

  raise notice '혐좋냥 emblem applied; cleared active guild penalties: %', v_penalty_target;
end;
$apply$;

commit;
