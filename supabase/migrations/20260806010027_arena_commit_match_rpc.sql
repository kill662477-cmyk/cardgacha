-- 투기장 매치 확정. Edge 가 양쪽 편성으로 전투를 재현한 결과를 받아 레이팅에 반영한다.
-- 공격자·방어자 양쪽이 함께 움직이되, 방어는 본인이 고른 판이 아니므로 변동폭을 줄인다.
create or replace function public.gacha_s2_arena_commit_match(
  p_user_id uuid,
  p_match_id uuid,
  p_attacker_won boolean,
  p_reason text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_match public.gacha_s2_arena_matches%rowtype;
  v_config jsonb;
  v_rules jsonb;
  v_k numeric;
  v_defender_scale numeric;
  v_min_rating integer;
  v_attacker_expected numeric;
  v_defender_expected numeric;
  v_attacker_after integer;
  v_defender_after integer;
  v_revision bigint;
  v_seed bigint;
  v_snapshot jsonb;
  v_response jsonb;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_request_hash text;
begin
  if p_user_id is null or p_match_id is null or p_attacker_won is null
    or p_reason is null or p_reason not in ('knockout', 'speed', 'survival', 'damage')
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 then
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '투기장 결과가 올바르지 않습니다.', 0, null, null);
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'arenaFight', 'matchId', p_match_id, 'attackerWon', p_attacker_won, 'reason', p_reason
  )::text, 'sha256'), 'hex');

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.command_type <> 'arenaFight' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등성 키를 다른 요청에 사용할 수 없습니다.', 0, null, null
      );
    end if;
    return v_previous.response;
  end if;

  select * into v_match from public.gacha_s2_arena_matches
  where match_id = p_match_id and attacker_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '투기장 매치를 찾을 수 없습니다.', 0, null, null);
  end if;
  if v_match.status = 'resolved' then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '이미 끝난 매치입니다.', 0, null, null);
  end if;

  select config into v_config from public.gacha_s2_balance_versions where active;
  v_rules := v_config->'arenaRules';
  v_k := coalesce((v_rules->>'eloK')::numeric, 24);
  v_defender_scale := coalesce((v_rules->>'defenderDeltaScale')::numeric, 0.8);
  v_min_rating := coalesce((v_rules->>'minRating')::integer, 800);

  -- ELO. arena.js 의 arenaExpectedScore / arenaRatingDelta 와 같은 식이어야 한다.
  v_attacker_expected := 1 / (1 + power(10, (v_match.defender_rating_before - v_match.attacker_rating_before)::numeric / 400));
  v_defender_expected := 1 / (1 + power(10, (v_match.attacker_rating_before - v_match.defender_rating_before)::numeric / 400));

  v_attacker_after := greatest(v_min_rating, v_match.attacker_rating_before
    + round(v_k * ((case when p_attacker_won then 1 else 0 end) - v_attacker_expected))::integer);
  v_defender_after := greatest(v_min_rating, v_match.defender_rating_before
    + round(v_k * v_defender_scale * ((case when p_attacker_won then 0 else 1 end) - v_defender_expected))::integer);

  update public.gacha_s2_arena_matches
  set status = 'resolved',
      attacker_won = p_attacker_won,
      reason = p_reason,
      attacker_rating_after = v_attacker_after,
      defender_rating_after = v_defender_after,
      resolved_at = now()
  where match_id = p_match_id;

  update public.gacha_s2_arena_players
  set rating = v_attacker_after,
      peak_rating = greatest(peak_rating, v_attacker_after),
      wins = wins + case when p_attacker_won then 1 else 0 end,
      losses = losses + case when p_attacker_won then 0 else 1 end,
      updated_at = now()
  where user_id = v_match.attacker_id;

  perform public.gacha_s2_arena_ensure_player(v_match.defender_id);
  update public.gacha_s2_arena_players
  set rating = v_defender_after,
      peak_rating = greatest(peak_rating, v_defender_after),
      defend_wins = defend_wins + case when p_attacker_won then 0 else 1 end,
      defend_losses = defend_losses + case when p_attacker_won then 1 else 0 end,
      updated_at = now()
  where user_id = v_match.defender_id;

  select revision into v_revision from public.gacha_s2_player_states where user_id = p_user_id;
  v_seed := public.gacha_s2_new_seed();
  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true,
    'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', v_seed,
    'snapshot', v_snapshot,
    'result', jsonb_build_object(
      'matchId', p_match_id,
      'won', p_attacker_won,
      'reason', p_reason,
      'ratingBefore', v_match.attacker_rating_before,
      'ratingAfter', v_attacker_after,
      'ratingDelta', v_attacker_after - v_match.attacker_rating_before,
      'opponentRatingBefore', v_match.defender_rating_before,
      'opponentRatingAfter', v_defender_after,
      'rank', public.gacha_s2_arena_rank_of(p_user_id)
    )
  );

  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response, expires_at)
  values (p_user_id, p_idempotency_key, 'arenaFight', v_request_hash, v_response, now() + interval '24 hours');
  insert into public.gacha_s2_command_audit (user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed)
  values (p_user_id, p_idempotency_key, 'arenaFight', v_request_hash, v_revision, v_revision, v_seed);

  return v_response;
end;
$$;

revoke all on function public.gacha_s2_arena_commit_match(uuid, uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_arena_commit_match(uuid, uuid, boolean, text, text) to service_role;
