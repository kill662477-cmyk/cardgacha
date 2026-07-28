-- 월드보스 HP 를 바꿔도 "이미 만들어진 회차"는 옛 값을 그대로 들고 있다.
-- gacha_s2_ensure_world_boss_schedule 은 currentSlot + nextSlot 을 미리 만들기 때문에,
-- 20시 회차가 시작되는 순간 다음날 17시 회차가 그때의 설정으로 생성된다.
-- 그래서 20시 이후에 설정을 바꾸면 다음날 17시만 옛 값으로 남는 구멍이 있었다.
-- (2026-07-28 17시가 75억이어야 하는데 65억으로 열려 59초 만에 처치된 사고.)
--
-- 앞으로 HP 를 바꾸는 마이그레이션은 마지막에 이 함수를 호출해서 아직 시작하지 않은
-- 회차를 현재 설정으로 맞춘다. 이미 딜이 들어간 회차(player_damage > 0)는 절대 건드리지 않는다.
create or replace function public.gacha_s2_resync_world_boss_hp(p_from timestamptz)
returns table(event_id text, max_hp bigint)
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_config jsonb;
begin
  select config into v_config from public.gacha_s2_balance_versions where active;
  if v_config is null then
    raise exception 'active balance version not found';
  end if;

  return query
  update public.gacha_s2_world_boss_events e
  set max_hp = t.cfg_max_hp,
      current_hp = t.cfg_max_hp,
      server_damage_per_second = t.cfg_dps,
      updated_at = now()
  from (
    select w.event_id,
           coalesce(
             (v_config->'worldBossRules'->'slotTiers'->((right(w.event_id, 2))::integer)::text->>'maxHp')::bigint,
             (v_config->'worldBossRules'->>'maxHp')::bigint
           ) as cfg_max_hp,
           coalesce(
             (v_config->'worldBossRules'->'slotTiers'->((right(w.event_id, 2))::integer)::text->>'serverDamagePerSecond')::bigint,
             (v_config->'worldBossRules'->>'serverDamagePerSecond')::bigint
           ) as cfg_dps
    from public.gacha_s2_world_boss_events w
    where w.starts_at >= p_from
      and w.player_damage = 0
  ) t
  where e.event_id = t.event_id
    and e.max_hp is distinct from t.cfg_max_hp
  returning e.event_id, e.max_hp;
end;
$fn$;

revoke all on function public.gacha_s2_resync_world_boss_hp(timestamptz) from public, anon, authenticated;
grant execute on function public.gacha_s2_resync_world_boss_hp(timestamptz) to service_role;

-- 지금 시점 정합성 확인: 아직 시작 안 한 회차가 설정과 어긋나면 여기서 맞춰진다.
select public.gacha_s2_resync_world_boss_hp(now());
