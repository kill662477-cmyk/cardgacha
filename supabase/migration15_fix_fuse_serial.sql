-- Fix gacha_fuse: its output column "serial" conflicted with an unqualified ORDER BY serial.
create or replace function public.gacha_fuse(
  p_user_id uuid,
  p_consume jsonb,
  p_success boolean,
  p_result_card_id text,
  p_points_gain integer,
  p_score_gain integer
) returns table(points integer, ranking_score integer, serial bigint)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user public.gacha_users%rowtype;
  v_item record;
  v_actual integer;
  v_result_serial bigint;
begin
  if jsonb_typeof(p_consume) <> 'array' or jsonb_array_length(p_consume) < 1 then
    raise exception 'invalid fuse input';
  end if;
  if p_points_gain < 0 or p_score_gain < 0 then
    raise exception 'invalid fuse input';
  end if;
  if p_success and (p_result_card_id is null or length(p_result_card_id) < 1) then
    raise exception 'invalid fuse input';
  end if;

  select * into v_user from public.gacha_users where id = p_user_id for update;
  if not found then raise exception 'user not found'; end if;

  for v_item in
    select * from jsonb_to_recordset(p_consume)
      as x(card_id text, expected_count integer, new_count integer)
  loop
    if v_item.card_id is null or v_item.expected_count is null or v_item.new_count is null
      or v_item.expected_count < 2 or v_item.new_count < 1 or v_item.new_count >= v_item.expected_count then
      raise exception 'invalid fuse input';
    end if;
    select count into v_actual from public.gacha_collection
    where user_id = p_user_id and card_id = v_item.card_id for update;
    if not found or v_actual <> v_item.expected_count then
      raise exception 'state changed' using errcode = 'P0001';
    end if;
    update public.gacha_collection set count = v_item.new_count
    where user_id = p_user_id and card_id = v_item.card_id;

    delete from public.gacha_card_serials
    where id in (
      select serial_rows.id from public.gacha_card_serials serial_rows
      where serial_rows.user_id = p_user_id and serial_rows.card_id = v_item.card_id
      order by serial_rows.serial desc
      limit (v_item.expected_count - v_item.new_count)
    );
  end loop;

  if p_success then
    insert into public.gacha_collection(user_id, card_id, count)
    values (p_user_id, p_result_card_id, 1)
    on conflict (user_id, card_id) do update
    set count = public.gacha_collection.count + 1;

    insert into public.gacha_card_counters(card_id, issued)
    values (p_result_card_id, 1)
    on conflict (card_id) do update
    set issued = public.gacha_card_counters.issued + 1
    returning issued into v_result_serial;

    insert into public.gacha_card_serials(user_id, card_id, serial, acquired_via)
    values (p_user_id, p_result_card_id, v_result_serial, 'fuse');
  end if;

  return query
  update public.gacha_users
  set points = public.gacha_users.points + p_points_gain,
      ranking_score = coalesce(public.gacha_users.ranking_score, 0) + p_score_gain
  where id = p_user_id
  returning public.gacha_users.points, public.gacha_users.ranking_score, v_result_serial;
end;
$$;

revoke all on function public.gacha_fuse(uuid, jsonb, boolean, text, integer, integer) from public;
grant execute on function public.gacha_fuse(uuid, jsonb, boolean, text, integer, integer) to service_role;
