-- EX/group cards are not race-synergy cards. Keep their snapshot race null so
-- the v2 client validator only receives 저그/테란/프로토스 for combat cards.
begin;

do $snapshot_ex_compat$
declare
  v_def text;
  v_next text;
  v_old text := ', ''race'', coalesce(c.race_override, (select catalog.race from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id))';
  v_new text := ', ''race'', case when exists (select 1 from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id and (catalog.rarity = ''EX'' or catalog.is_group)) then null else coalesce(c.race_override, (select catalog.race from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id)) end';
begin
  select pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure) into v_def;
  if strpos(v_def, v_new) = 0 then
    v_next := replace(v_def, v_old, v_new);
    if v_next = v_def or strpos(v_next, v_new) = 0 then
      raise exception 'player snapshot EX race compatibility source mismatch';
    end if;
    execute v_next;
  end if;
end;
$snapshot_ex_compat$;

do $verify$
declare
  v_source text;
begin
  v_source := pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure);
  if v_source not like '%catalog.rarity = ''EX'' or catalog.is_group%'
    or v_source not like '%then null else coalesce(c.race_override%' then
    raise exception 'player snapshot EX race compatibility verification failed';
  end if;
end;
$verify$;

commit;
