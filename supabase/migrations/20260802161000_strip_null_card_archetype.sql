-- EX cards have no combat archetype. Keep null values out of account snapshots
-- so older clients do not reject otherwise valid player state.

begin;

do $snapshot_fix$
declare
  v_def text;
  v_next text;
  v_source text := 'jsonb_build_object(''enhancement'', c.enhancement, ''exp'', c.card_exp, ''archetype'', coalesce(c.archetype_override, (select catalog.archetype from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id)))';
begin
  select pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure) into v_def;
  v_next := replace(v_def, v_source, 'jsonb_strip_nulls(' || v_source || ')');
  if v_next = v_def or strpos(v_next, 'jsonb_strip_nulls(jsonb_build_object(''enhancement'', c.enhancement') = 0 then
    raise exception 'player snapshot null archetype fix source mismatch';
  end if;
  execute v_next;
end;
$snapshot_fix$;

do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure) into v_def;
  if strpos(v_def, 'jsonb_strip_nulls(jsonb_build_object(''enhancement'', c.enhancement') = 0 then
    raise exception 'player snapshot null archetype fix verification failed';
  end if;
end;
$verify$;

commit;
