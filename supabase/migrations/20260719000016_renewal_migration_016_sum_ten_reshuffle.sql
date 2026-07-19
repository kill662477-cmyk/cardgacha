-- Card Gacha Season 2: 사과게임(sumTen) deadlock reshuffle + reward rescale.
--
-- 1) Board can now reshuffle in place when no sum-10 rectangle remains, so a run
--    is no longer soft-locked until the timer expires. Reshuffle is deterministic
--    (fixed arrangements, no RNG) so this verify RPC reproduces the client's board
--    exactly while replaying the input log -- no extra data is trusted from the
--    client. Mirrors src/renewal/minigames.js hasValidSumMove / reshuffleSumTiles.
-- 2) sumTen reward rescaled so a strong single game can approach the 3000P daily
--    cap: rewardPerScore 1 -> 17, maxReward 240 -> 3000. Reward is read from the
--    balance version config at runtime, so the stored config JSON is patched here.
--
-- No new tables, no extra edge invocations, no realtime: still one verify call per
-- finishMinigame. Only per-call CPU rises (bounded rectangle scan, short-circuited).

-- True when some axis-aligned rectangle of active tiles sums to exactly 10.
-- 2D prefix sum over active values; each rectangle O(1); returns on first hit.
create or replace function public.gacha_s2_sum_ten_has_move(
  p_active boolean[],
  p_values integer[]
) returns boolean
language plpgsql
immutable
strict
as $$
declare
  c constant integer := 17;
  r constant integer := 10;
  w constant integer := 18; -- columns + 1
  pre integer[] := array_fill(0, array[(r + 1) * w]);
  vr integer;
  vc integer;
  r1 integer;
  c1 integer;
  r2 integer;
  c2 integer;
  cell integer;
  s integer;
begin
  for vr in 0 .. r - 1 loop
    for vc in 0 .. c - 1 loop
      if p_active[vr * c + vc + 1] then
        cell := p_values[vr * c + vc + 1];
      else
        cell := 0;
      end if;
      pre[(vr + 1) * w + (vc + 1) + 1] := cell
        + pre[vr * w + (vc + 1) + 1]
        + pre[(vr + 1) * w + vc + 1]
        - pre[vr * w + vc + 1];
    end loop;
  end loop;
  for r1 in 0 .. r - 1 loop
    for r2 in r1 .. r - 1 loop
      for c1 in 0 .. c - 1 loop
        for c2 in c1 .. c - 1 loop
          s := pre[(r2 + 1) * w + (c2 + 1) + 1]
             - pre[r1 * w + (c2 + 1) + 1]
             - pre[(r2 + 1) * w + c1 + 1]
             + pre[r1 * w + c1 + 1];
          if s = 10 then
            return true;
          end if;
        end loop;
      end loop;
    end loop;
  end loop;
  return false;
end;
$$;

-- Deterministic deadlock rescue. Redistributes remaining active values into their
-- positions using fixed arrangements (zigzag / ascending / descending / rotated
-- zigzag) and returns the first that restores a valid move, or null if the leftover
-- multiset can never sum to 10 (caller ends the game). Must match the client.
create or replace function public.gacha_s2_sum_ten_reshuffle(
  p_active boolean[],
  p_values integer[]
) returns integer[]
language plpgsql
immutable
strict
as $$
declare
  attempts constant integer := 4;
  positions integer[] := '{}';
  vals integer[] := '{}';
  asc_vals integer[];
  arranged integer[];
  next_values integer[];
  m integer;
  i integer;
  lo integer;
  hi integer;
  a integer;
begin
  for i in 1 .. 170 loop
    if p_active[i] then
      positions := array_append(positions, i);
      vals := array_append(vals, p_values[i]);
    end if;
  end loop;
  m := coalesce(array_length(positions, 1), 0);
  if m = 0 then
    return null;
  end if;
  select array_agg(x order by x) into asc_vals from unnest(vals) as t(x);
  for a in 0 .. attempts - 1 loop
    if a = 0 or a = 3 then
      arranged := '{}';
      lo := 1;
      hi := m;
      while lo <= hi loop
        arranged := array_append(arranged, asc_vals[lo]);
        lo := lo + 1;
        if lo <= hi then
          arranged := array_append(arranged, asc_vals[hi]);
          hi := hi - 1;
        end if;
      end loop;
      if a = 3 and m > 1 then
        arranged := arranged[2:m] || arranged[1:1];
      end if;
    elsif a = 1 then
      arranged := asc_vals;
    else
      select array_agg(x order by x desc) into arranged from unnest(asc_vals) as t(x);
    end if;
    next_values := p_values;
    for i in 1 .. m loop
      next_values[positions[i]] := arranged[i];
    end loop;
    if public.gacha_s2_sum_ten_has_move(p_active, next_values) then
      return next_values;
    end if;
  end loop;
  return null;
end;
$$;

-- Replay verify with in-place reshuffle mirrored from the client.
create or replace function public.gacha_s2_verify_sum_ten_log(
  p_board jsonb,
  p_input_log jsonb,
  p_time_limit_seconds integer,
  p_server_elapsed_ms bigint
) returns jsonb
language plpgsql
immutable
strict
as $$
declare
  v_count integer := jsonb_array_length(p_board);
  v_active boolean[];
  v_values integer[];
  v_reshuffled integer[];
  v_action jsonb;
  v_start integer;
  v_end integer;
  v_at_ms bigint;
  v_previous_at bigint := 0;
  v_max_at bigint := least(p_time_limit_seconds::bigint * 1000, p_server_elapsed_ms + 1000);
  v_start_row integer;
  v_end_row integer;
  v_start_column integer;
  v_end_column integer;
  v_min_row integer;
  v_max_row integer;
  v_min_column integer;
  v_max_column integer;
  v_index integer;
  v_row integer;
  v_column integer;
  v_sum integer;
  v_selected integer;
  v_score integer := 0;
  v_remaining integer := 170;
begin
  if v_count <> 170 or jsonb_array_length(p_input_log) > 500 then
    return jsonb_build_object('valid', false, 'reason', 'INVALID_LOG_SIZE');
  end if;
  v_active := array_fill(true, array[v_count]);
  v_values := array(select (p_board->>gs)::integer from generate_series(0, v_count - 1) as gs);
  -- Initial deadlock guard (mirrors client): reshuffle a dead board, else play as dealt.
  if not public.gacha_s2_sum_ten_has_move(v_active, v_values) then
    v_reshuffled := public.gacha_s2_sum_ten_reshuffle(v_active, v_values);
    if v_reshuffled is not null then
      v_values := v_reshuffled;
    end if;
  end if;
  for v_action in select value from jsonb_array_elements(p_input_log) loop
    if jsonb_typeof(v_action) <> 'object'
      or coalesce(v_action->>'start', '') !~ '^\d+$'
      or coalesce(v_action->>'end', '') !~ '^\d+$'
      or coalesce(v_action->>'atMs', '') !~ '^\d+$' then
      return jsonb_build_object('valid', false, 'reason', 'INVALID_ACTION');
    end if;
    v_start := (v_action->>'start')::integer;
    v_end := (v_action->>'end')::integer;
    v_at_ms := (v_action->>'atMs')::bigint;
    if v_start < 0 or v_start >= v_count or v_end < 0 or v_end >= v_count
      or v_at_ms < v_previous_at or v_at_ms > v_max_at then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION');
    end if;
    v_previous_at := v_at_ms;
    v_start_row := v_start / 17;
    v_end_row := v_end / 17;
    v_start_column := v_start % 17;
    v_end_column := v_end % 17;
    v_min_row := least(v_start_row, v_end_row);
    v_max_row := greatest(v_start_row, v_end_row);
    v_min_column := least(v_start_column, v_end_column);
    v_max_column := greatest(v_start_column, v_end_column);
    v_sum := 0;
    v_selected := 0;
    for v_index in 0 .. 169 loop
      v_row := v_index / 17;
      v_column := v_index % 17;
      if v_active[v_index + 1]
        and v_row between v_min_row and v_max_row
        and v_column between v_min_column and v_max_column then
        v_sum := v_sum + v_values[v_index + 1];
        v_selected := v_selected + 1;
      end if;
    end loop;
    if v_selected > 0 and v_sum = 10 then
      for v_index in 0 .. 169 loop
        v_row := v_index / 17;
        v_column := v_index % 17;
        if v_active[v_index + 1]
          and v_row between v_min_row and v_max_row
          and v_column between v_min_column and v_max_column then
          v_active[v_index + 1] := false;
          v_remaining := v_remaining - 1;
        end if;
      end loop;
      v_score := v_score + v_selected;
      -- Reshuffle guard after a clear (mirrors client): only when tiles remain.
      if v_remaining > 0 and not public.gacha_s2_sum_ten_has_move(v_active, v_values) then
        v_reshuffled := public.gacha_s2_sum_ten_reshuffle(v_active, v_values);
        if v_reshuffled is not null then
          v_values := v_reshuffled;
        end if;
      end if;
    end if;
  end loop;
  return jsonb_build_object(
    'valid', true,
    'score', v_score,
    'completed', v_remaining = 0,
    'remainingTiles', v_remaining
  );
end;
$$;

-- Rescale sumTen reward in the active balance config (runtime source of truth).
update public.gacha_s2_balance_versions
set config = jsonb_set(
      jsonb_set(config, '{miniGameRules,sumTen,maxReward}', '3000'::jsonb, false),
      '{miniGameRules,sumTen,rewardPerScore}', '17'::jsonb, false
    ),
    config_hash = '23952e3e806147ec7d6a723a18290c63c48935a22ca3263c4eadf73a38ccac47'
where version = '2026.07.18-random-loot-1';

revoke all on function public.gacha_s2_sum_ten_has_move(boolean[], integer[]) from public, anon, authenticated;
revoke all on function public.gacha_s2_sum_ten_reshuffle(boolean[], integer[]) from public, anon, authenticated;
