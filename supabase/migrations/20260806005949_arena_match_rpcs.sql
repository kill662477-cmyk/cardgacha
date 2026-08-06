-- 투기장 매치 개시. 행동력·횟수를 검사하고 상대를 골라 대기 매치를 만든다.
-- 상대 고르기가 이 안에서 끝나야 클라이언트가 마음에 드는 상대가 나올 때까지
-- 다시 굴리는 것을 막을 수 있다. 그래서 여기서 행동력과 횟수를 먼저 소모한다.
create or replace function public.gacha_s2_arena_open_match(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
  v_revision bigint;
  v_energy integer;
  v_formation text[];
  v_config jsonb;
  v_rules jsonb;
  v_energy_cost integer;
  v_attempts_per_hour integer;
  v_used integer;
  v_self public.gacha_s2_arena_players%rowtype;
  v_band integer;
  v_bands jsonb;
  v_opponent uuid;
  v_opponent_rating integer;
  v_match public.gacha_s2_arena_matches%rowtype;
  v_week text;
  v_existing public.gacha_s2_arena_matches%rowtype;
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '투기장 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  -- 같은 커맨드로 다시 들어오면 이미 만든 매치를 그대로 돌려준다(중복 소모 방지).
  select * into v_existing from public.gacha_s2_arena_matches
  where attacker_id = p_user_id and command_id = p_idempotency_key;
  if found then
    return jsonb_build_object(
      'ok', true, 'matchId', v_existing.match_id, 'replayed', true,
      'attackerId', v_existing.attacker_id, 'defenderId', v_existing.defender_id,
      'status', v_existing.status
    );
  end if;

  select revision, action_energy, formation into v_revision, v_energy, v_formation
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와야 합니다.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null
    );
  end if;
  if v_formation is null or array_length(v_formation, 1) is distinct from 5 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '편성 5장을 먼저 채워야 합니다.', v_revision, null, null
    );
  end if;

  select config into v_config from public.gacha_s2_balance_versions where active;
  v_rules := v_config->'arenaRules';
  if v_rules is null then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '투기장 설정이 없습니다.', v_revision, null, null);
  end if;
  v_energy_cost := coalesce((v_rules->>'energyCost')::integer, 5);
  v_attempts_per_hour := coalesce((v_rules->>'attemptsPerHour')::integer, 3);
  v_bands := coalesce(v_rules->'matchRatingBands', '[100,200,400]'::jsonb);

  if v_energy < v_energy_cost then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', format('행동력 %s이 필요합니다.', v_energy_cost),
      v_revision, null, jsonb_build_object('requiredEnergy', v_energy_cost)
    );
  end if;

  v_used := public.gacha_s2_arena_attempts_used(p_user_id, v_now);
  if v_used >= v_attempts_per_hour then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이번 시간대 투기장 횟수를 모두 썼습니다.',
      v_revision, null, jsonb_build_object(
        'attemptsPerHour', v_attempts_per_hour,
        'resetsAt', floor(extract(epoch from (date_trunc('hour', v_now) + interval '1 hour')) * 1000)::bigint
      )
    );
  end if;

  v_self := public.gacha_s2_arena_ensure_player(p_user_id);

  -- 비슷한 레이팅부터 찾고, 없으면 폭을 넓힌다. 편성이 5장인 상대만 고른다.
  for v_band in select (value)::integer from jsonb_array_elements_text(v_bands) loop
    select p.user_id, a.rating into v_opponent, v_opponent_rating
    from public.gacha_s2_arena_players a
    join public.gacha_s2_player_states p on p.user_id = a.user_id
    join public.gacha_s2_accounts acc on acc.id = a.user_id
    where a.user_id <> p_user_id
      and acc.is_streamer = false
      and acc.disabled_at is null
      and p.formation is not null
      and array_length(p.formation, 1) = 5
      and abs(a.rating - v_self.rating) <= v_band
    order by random()
    limit 1;
    exit when v_opponent is not null;
  end loop;

  if v_opponent is null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '지금은 상대를 찾을 수 없습니다. 잠시 후 다시 시도해 주세요.',
      v_revision, null, null
    );
  end if;

  v_week := public.gacha_s2_arena_week_key(v_now);

  insert into public.gacha_s2_arena_matches (
    attacker_id, defender_id, command_id,
    attacker_rating_before, defender_rating_before,
    attacker_formation, defender_formation, week_key
  )
  select p_user_id, v_opponent, p_idempotency_key,
         v_self.rating, v_opponent_rating,
         to_jsonb(v_formation), to_jsonb(defender.formation), v_week
  from public.gacha_s2_player_states defender
  where defender.user_id = v_opponent
  returning * into v_match;

  -- 상대를 확정한 시점에 자원을 소모한다. 여기서 실패하면 매치도 롤백된다.
  update public.gacha_s2_player_states
  set action_energy = action_energy - v_energy_cost,
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id;

  update public.gacha_s2_arena_players
  set week_attacks = case when week_key is distinct from v_week then 1 else week_attacks + 1 end,
      week_key = v_week,
      last_match_at = v_now,
      updated_at = now()
  where user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'matchId', v_match.match_id,
    'replayed', false,
    'attackerId', p_user_id,
    'defenderId', v_opponent,
    'attackerRating', v_self.rating,
    'defenderRating', v_opponent_rating,
    'attemptsUsed', v_used + 1,
    'attemptsPerHour', v_attempts_per_hour
  );
end;
$$;

revoke all on function public.gacha_s2_arena_open_match(uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_arena_open_match(uuid, bigint, text) to service_role;
