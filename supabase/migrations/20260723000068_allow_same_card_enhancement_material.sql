-- Allow excess copies of the locked enhancement target to be consumed as materials.
-- The existing owned.copies - 1 validation still preserves the target's base copy.

do $migration$
declare
  v_signature regprocedure := to_regprocedure(
    'public.gacha_s2_enhance_card(uuid,bigint,text,text,integer,text[],text)'
  );
  v_definition text;
  v_patched_definition text;
begin
  if v_signature is null then
    raise exception 'gacha_s2_enhance_card signature not found';
  end if;

  select pg_get_functiondef(v_signature) into v_definition;
  v_patched_definition := replace(
    v_definition,
    'or owned.locked',
    'or (owned.locked and req.card_id <> p_card_id)'
  );

  if v_patched_definition = v_definition then
    raise exception 'gacha_s2_enhance_card locked-material guard was not found';
  end if;

  execute v_patched_definition;
end;
$migration$;

revoke all on function public.gacha_s2_enhance_card(uuid, bigint, text, text, integer, text[], text)
  from public, anon, authenticated;
grant execute on function public.gacha_s2_enhance_card(uuid, bigint, text, text, integer, text[], text)
  to service_role;
