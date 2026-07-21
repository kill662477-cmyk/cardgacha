create or replace function public.gacha_s2_verify_memory_log(
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
  v_action jsonb;
  v_start integer;
  v_end integer;
  v_at_ms bigint;
  v_previous_at bigint := 0;
  v_max_at bigint := least((p_time_limit_seconds::bigint + 15) * 1000, p_server_elapsed_ms + 10000);
  v_matches integer := 0;
  v_streak integer := 0;
  v_score integer := 0;
  v_valid_match boolean;
begin
  if v_count % 2 <> 0 or jsonb_array_length(p_input_log) > 500 then
    return jsonb_build_object('valid', false, 'reason', 'INVALID_LOG_SIZE');
  end if;
  v_active := array_fill(true, array[v_count]);
  for v_action in select value from jsonb_array_elements(p_input_log) loop
    if jsonb_typeof(v_action) <> 'object'
      or v_action->>'start' is null
      or v_action->>'end' is null
      or v_action->>'atMs' is null then
      return jsonb_build_object('valid', false, 'reason', 'INVALID_ACTION_FORMAT');
    end if;
    v_start := floor((v_action->>'start')::numeric)::integer;
    v_end := floor((v_action->>'end')::numeric)::integer;
    v_at_ms := floor((v_action->>'atMs')::numeric)::bigint;

    if v_start < 0 or v_start >= v_count or v_end < 0 or v_end >= v_count or v_start = v_end then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_BOUNDS');
    end if;
    if not v_active[v_start + 1] or not v_active[v_end + 1] then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_ALREADY_FLIPPED');
    end if;
    if v_at_ms < v_previous_at then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_TIME_BACKWARDS');
    end if;
    if v_at_ms > v_max_at then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_TIME_EXCEEDED');
    end if;
    v_previous_at := v_at_ms;

    v_valid_match := (p_board->>v_start) = (p_board->>v_end);
    if v_valid_match then
      v_active[v_start + 1] := false;
      v_active[v_end + 1] := false;
      v_matches := v_matches + 1;
      v_streak := v_streak + 1;
      v_score := v_score + 100 + v_streak * 20;
    else
      v_streak := 0;
      v_score := greatest(0, v_score - 10);
    end if;
  end loop;
  return jsonb_build_object(
    'valid', true,
    'score', v_score,
    'completed', v_matches * 2 = v_count
  );
end;
$$;

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
  v_max_at bigint := least((p_time_limit_seconds::bigint + 15) * 1000, p_server_elapsed_ms + 10000);
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
  
  if not public.gacha_s2_sum_ten_has_move(v_active, v_values) then
    v_reshuffled := public.gacha_s2_sum_ten_reshuffle(v_active, v_values);
    if v_reshuffled is not null then
      v_values := v_reshuffled;
    end if;
  end if;

  for v_action in select value from jsonb_array_elements(p_input_log) loop
    if jsonb_typeof(v_action) <> 'object'
      or v_action->>'start' is null
      or v_action->>'end' is null
      or v_action->>'atMs' is null then
      return jsonb_build_object('valid', false, 'reason', 'INVALID_ACTION_FORMAT');
    end if;
    v_start := floor((v_action->>'start')::numeric)::integer;
    v_end := floor((v_action->>'end')::numeric)::integer;
    v_at_ms := floor((v_action->>'atMs')::numeric)::bigint;

    if v_start < 0 or v_start >= v_count or v_end < 0 or v_end >= v_count or v_at_ms < v_previous_at or v_at_ms > v_max_at then
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
