-- 고급 작전 지원팩 확정 지급 진행도를 플레이어 스냅샷에 실어 보낸다.
-- 클라이언트가 상점에서 "확정까지 얼마 남았는지"를 보여주기 위한 값이다.
-- threshold 는 밸런스 설정에서 읽으므로 임계값을 바꾸면 표시도 같이 따라간다.
create or replace function public.gacha_s2_get_player_snapshot(p_user_id uuid)
returns jsonb
language sql
stable security definer
set search_path = public, pg_temp
as $function$
  select jsonb_build_object(
    'schemaVersion', s.schema_version, 'revision', s.revision, 'nickname', a.nickname,
    'actionEnergy', s.action_energy, 'maxActionEnergy', s.max_action_energy,
    'lastEnergyAt', floor(extract(epoch from s.last_energy_at) * 1000)::bigint,
    'points', s.points, 'clearedStage', s.cleared_stage, 'pendingPoints', s.pending_points,
    'lastRewardAt', floor(extract(epoch from s.last_reward_at) * 1000)::bigint,
    'quickBattle', s.quick_battle, 'adventureRuns', s.adventure_runs, 'adventureRun', s.adventure_run,
    'cardProgress', coalesce((
      select jsonb_object_agg(c.card_id, jsonb_strip_nulls(jsonb_build_object('enhancement', c.enhancement, 'exp', c.card_exp, 'archetype', coalesce(c.archetype_override, (select catalog.archetype from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id)))))
      from public.gacha_s2_player_cards c where c.user_id = s.user_id), '{}'::jsonb),
    'cardCopies', coalesce((
      select jsonb_object_agg(c.card_id, c.copies)
      from public.gacha_s2_player_cards c where c.user_id = s.user_id), '{}'::jsonb),
    'cardLocks', coalesce((
      select jsonb_object_agg(c.card_id, c.locked)
      from public.gacha_s2_player_cards c where c.user_id = s.user_id), '{}'::jsonb),
    'collectionRecords', coalesce((
      select jsonb_object_agg(r.card_id, true)
      from public.gacha_s2_collection_records r where r.user_id = s.user_id), '{}'::jsonb),
    'supportItems', s.support_items, 'activeBuffs', s.active_buffs,
    'shopTransactions', s.shop_transactions, 'enhancementAttempts', s.enhancement_attempts,
    'miniGames', s.mini_games, 'worldBoss', s.world_boss,
    'exMilestoneClaims', s.ex_milestone_claims, 'representativeCardId', s.representative_card_id,
    'formation', to_jsonb(s.formation), 'formationPresets', s.formation_presets,
    'activeFormationPresetId', s.active_formation_preset_id, 'miniGameRuns', '[]'::jsonb,
    'powerRanking', jsonb_build_object(
      'seasonId', 'season-2',
      'snapshotAt', coalesce(floor(extract(epoch from s.power_snapshot_at) * 1000)::bigint, 0),
      'power', s.power_snapshot, 'rank', null, 'population', 0),
    'guildBuff', public.gacha_s2_guild_buff(s.user_id),
    -- 고급팩 확정 지급 진행도. 누적 행이 없으면 0 으로 내려간다.
    'advancedPackPity', jsonb_build_object(
      'spent', coalesce((
        select pity.spent_since_grant from public.gacha_s2_advanced_pack_trait_pity pity
        where pity.user_id = s.user_id), 0),
      'granted', coalesce((
        select pity.granted_count from public.gacha_s2_advanced_pack_trait_pity pity
        where pity.user_id = s.user_id), 0),
      'threshold', coalesce((
        select (b.config->'advancedSupportPack'->>'guaranteedTraitRerollPoints')::bigint
        from public.gacha_s2_balance_versions b where b.active), 0)
    )
  )
  from public.gacha_s2_player_states s
  join public.gacha_s2_accounts a on a.id = s.user_id
  where s.user_id = p_user_id;
$function$;

do $$
declare v jsonb;
begin
  select public.gacha_s2_get_player_snapshot(user_id) into v
  from public.gacha_s2_player_states limit 1;
  if v->'advancedPackPity' is null then
    raise exception 'advancedPackPity missing from snapshot';
  end if;
  if (v->'advancedPackPity'->>'threshold')::bigint <> 3000000 then
    raise exception 'advancedPackPity threshold wrong: %', v->'advancedPackPity'->>'threshold';
  end if;
end;
$$;
