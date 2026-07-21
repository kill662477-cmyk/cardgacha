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
  v_matched boolean[];
  v_open integer[] := '{}'::integer[];
  v_action jsonb;
  v_index integer;
  v_at_ms bigint;
  v_previous_at bigint := 0;
  v_max_at bigint := least((p_time_limit_seconds::bigint + 15) * 1000, p_server_elapsed_ms + 10000);
  v_left integer;
  v_right integer;
  v_streak integer := 0;
  v_score integer := 0;
  v_matches integer := 0;
begin
  if v_count not in (16, 36) or jsonb_array_length(p_input_log) > 500 then
    return jsonb_build_object('valid', false, 'reason', 'INVALID_LOG_SIZE');
  end if;
  v_matched := array_fill(false, array[v_count]);
  for v_action in select value from jsonb_array_elements(p_input_log) loop
    if jsonb_typeof(v_action) <> 'object'
      or coalesce(v_action->>'index', '') !~ '^\d+$'
      or coalesce(v_action->>'atMs', '') !~ '^\d+$' then
      return jsonb_build_object('valid', false, 'reason', 'INVALID_ACTION_FORMAT');
    end if;
    v_index := (v_action->>'index')::integer;
    v_at_ms := (v_action->>'atMs')::bigint;

    if v_index < 0 or v_index >= v_count then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_BOUNDS');
    end if;
    if v_matched[v_index + 1] then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_ALREADY_FLIPPED');
    end if;
    if array_position(v_open, v_index) is not null then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_ALREADY_OPEN');
    end if;
    if v_at_ms < v_previous_at then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_TIME_BACKWARDS', 'atMs', v_at_ms, 'prevMs', v_previous_at);
    end if;
    if v_at_ms > v_max_at then
      return jsonb_build_object('valid', false, 'reason', 'ILLEGAL_ACTION_TIME_EXCEEDED', 'atMs', v_at_ms, 'maxMs', v_max_at);
    end if;
    
    v_previous_at := v_at_ms;
    v_open := array_append(v_open, v_index);
    
    if array_length(v_open, 1) = 2 then
      v_left := v_open[1];
      v_right := v_open[2];
      v_open := '{}'::integer[];
      if (p_board->>v_left) = (p_board->>v_right) then
        v_matched[v_left + 1] := true;
        v_matched[v_right + 1] := true;
        v_matches := v_matches + 1;
        v_streak := v_streak + 1;
        v_score := v_score + 100 + v_streak * 20;
      else
        v_streak := 0;
        v_score := greatest(0, v_score - 10);
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'valid', true,
    'score', v_score,
    'completed', v_matches * 2 = v_count
  );
end;
$$;
