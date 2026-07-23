-- The previous migration treated energyCost and dailyPointCapPerGame as
-- game-specific settings. Both values live directly under miniGameRules.
-- The start function also kept expired runs active for a 15-second finish grace
-- period. Keep that grace in finish, but do not let it block the next game.
-- Patch the deployed function bodies in place so all other hotfixes remain intact.

do $migration$
declare
  v_start_definition text;
  v_finish_definition text;
  v_original_definition text;
begin
  select pg_get_functiondef(
    'public.gacha_s2_start_minigame(uuid,bigint,text,text,text)'::regprocedure
  ) into v_start_definition;
  v_original_definition := v_start_definition;

  if position($broken$(v_config->'miniGameRules'->p_game->>'dailyPointCapPerGame')::integer$broken$ in v_start_definition) = 0
    or position($broken$(v_config->'miniGameRules'->p_game->>'energyCost')::integer$broken$ in v_start_definition) = 0
    or position($broken$expires_at + interval '15 seconds' >= now()$broken$ in v_start_definition) = 0
    or position($broken$expires_at + interval '15 seconds' < now()$broken$ in v_start_definition) = 0 then
    raise exception 'Expected broken minigame start rule paths were not found';
  end if;

  v_start_definition := replace(
    v_start_definition,
    $broken$(v_config->'miniGameRules'->p_game->>'dailyPointCapPerGame')::integer$broken$,
    $fixed$(v_config->'miniGameRules'->>'dailyPointCapPerGame')::integer$fixed$
  );
  v_start_definition := replace(
    v_start_definition,
    $broken$(v_config->'miniGameRules'->p_game->>'energyCost')::integer$broken$,
    $fixed$(v_config->'miniGameRules'->>'energyCost')::integer$fixed$
  );
  v_start_definition := replace(
    v_start_definition,
    $broken$expires_at + interval '15 seconds' >= now()$broken$,
    $fixed$expires_at >= now()$fixed$
  );
  v_start_definition := replace(
    v_start_definition,
    $broken$expires_at + interval '15 seconds' < now()$broken$,
    $fixed$expires_at < now()$fixed$
  );

  if v_start_definition = v_original_definition then
    raise exception 'Minigame start rule paths were not changed';
  end if;
  execute v_start_definition;

  select pg_get_functiondef(
    'public.gacha_s2_finish_minigame(uuid,bigint,text,uuid,jsonb,integer)'::regprocedure
  ) into v_finish_definition;
  v_original_definition := v_finish_definition;

  if position($broken$(v_config->'miniGameRules'->v_run.game->>'dailyPointCapPerGame')::integer$broken$ in v_finish_definition) = 0 then
    raise exception 'Expected broken minigame finish rule path was not found';
  end if;

  v_finish_definition := replace(
    v_finish_definition,
    $broken$(v_config->'miniGameRules'->v_run.game->>'dailyPointCapPerGame')::integer$broken$,
    $fixed$(v_config->'miniGameRules'->>'dailyPointCapPerGame')::integer$fixed$
  );

  if v_finish_definition = v_original_definition then
    raise exception 'Minigame finish rule path was not changed';
  end if;
  execute v_finish_definition;
end;
$migration$;
