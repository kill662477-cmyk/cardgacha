-- 길드 M2: 플레이어 스냅샷에 guildBuff 추가 (PDB-16 3.1)
--
-- 길드 스탯 버프는 전투 계산에 들어간다. 서버는 클라이언트가 보낸 전투 결과를
-- 같은 입력으로 재현해 검증하므로(server-command-router 의 verifiedContext),
-- 버프 값이 스냅샷에 실려 양쪽이 항상 같은 값을 보게 해야 한다.
-- 별도 조회로 두면 길드 화면에 들어가지 않은 클라이언트가 버프를 모른 채 전투를
-- 계산해 서버 검증과 어긋난다.
--
-- 기존 필드는 하나도 바꾸지 않고 guildBuff 만 덧붙인다. 소속이 없으면 전부 0 이라
-- 무소속 유저의 계산 결과는 이전과 동일하다.
create or replace function public.gacha_s2_get_player_snapshot(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'schemaVersion', s.schema_version,
    'revision', s.revision,
    'nickname', a.nickname,
    'actionEnergy', s.action_energy,
    'maxActionEnergy', s.max_action_energy,
    'lastEnergyAt', floor(extract(epoch from s.last_energy_at) * 1000)::bigint,
    'points', s.points,
    'clearedStage', s.cleared_stage,
    'pendingPoints', s.pending_points,
    'lastRewardAt', floor(extract(epoch from s.last_reward_at) * 1000)::bigint,
    'quickBattle', s.quick_battle,
    'adventureRuns', s.adventure_runs,
    'adventureRun', s.adventure_run,
    'cardProgress', coalesce((
      select jsonb_object_agg(c.card_id, jsonb_build_object('enhancement', c.enhancement, 'exp', c.card_exp))
      from public.gacha_s2_player_cards c where c.user_id = s.user_id
    ), '{}'::jsonb),
    'cardCopies', coalesce((
      select jsonb_object_agg(c.card_id, c.copies)
      from public.gacha_s2_player_cards c where c.user_id = s.user_id
    ), '{}'::jsonb),
    'cardLocks', coalesce((
      select jsonb_object_agg(c.card_id, c.locked)
      from public.gacha_s2_player_cards c where c.user_id = s.user_id
    ), '{}'::jsonb),
    'collectionRecords', coalesce((
      select jsonb_object_agg(r.card_id, true)
      from public.gacha_s2_collection_records r where r.user_id = s.user_id
    ), '{}'::jsonb),
    'supportItems', s.support_items,
    'activeBuffs', s.active_buffs,
    'shopTransactions', s.shop_transactions,
    'enhancementAttempts', s.enhancement_attempts,
    'miniGames', s.mini_games,
    'worldBoss', s.world_boss,
    'exMilestoneClaims', s.ex_milestone_claims,
    'representativeCardId', s.representative_card_id,
    'formation', to_jsonb(s.formation),
    'formationPresets', s.formation_presets,
    'activeFormationPresetId', s.active_formation_preset_id,
    'miniGameRuns', '[]'::jsonb,
    'powerRanking', jsonb_build_object(
      'seasonId', 'season-2',
      'snapshotAt', coalesce(floor(extract(epoch from s.power_snapshot_at) * 1000)::bigint, 0),
      'power', s.power_snapshot,
      'rank', null,
      'population', 0
    ),
    'guildBuff', public.gacha_s2_guild_buff(s.user_id)
  )
  from public.gacha_s2_player_states s
  join public.gacha_s2_accounts a on a.id = s.user_id
  where s.user_id = p_user_id;
$$;
