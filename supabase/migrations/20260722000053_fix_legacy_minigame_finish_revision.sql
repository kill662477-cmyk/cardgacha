-- Fix the legacy authenticated minigame finish RPC. It referenced a removed
-- p_expected_revision parameter in validation errors, making the function fail lint.

do $migration$
declare
  v_definition text;
  v_fixed_definition text;
begin
  select pg_get_functiondef(
    'public.gacha_s2_command_finish_minigame(text,uuid,jsonb,integer)'::regprocedure
  ) into v_definition;

  if position('p_expected_revision, null, null' in v_definition) = 0 then
    raise exception 'Expected stale minigame revision reference was not found';
  end if;

  v_fixed_definition := replace(
    v_definition,
    'p_expected_revision, null, null',
    'greatest(coalesce(v_expected_revision, 0), 0), null, null'
  );

  if position('p_expected_revision, null, null' in v_fixed_definition) > 0 then
    raise exception 'Stale minigame revision reference remains';
  end if;
  execute v_fixed_definition;
end;
$migration$;
