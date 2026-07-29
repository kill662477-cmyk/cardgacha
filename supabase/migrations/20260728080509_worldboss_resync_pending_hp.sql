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
grant execute on function public.gacha_s2_resync_world_boss_hp(timestamptz) to service_role;;
