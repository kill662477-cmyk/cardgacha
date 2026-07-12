-- SOOP 별풍선 1개당 후원자·방송인 각각 3P 지급.
create or replace function public.gacha_apply_soop_donation(
  p_event_id text,
  p_sender_soop_id text,
  p_recipient_soop_id text,
  p_amount integer
) returns table(applied boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inserted text;
  v_sender_user uuid;
  v_recipient_user uuid;
  v_sender_exists boolean := false;
  v_points integer;
begin
  if length(trim(p_event_id)) < 8 or length(trim(p_event_id)) > 255
    or length(trim(p_sender_soop_id)) < 1 or length(trim(p_sender_soop_id)) > 100
    or length(trim(p_recipient_soop_id)) < 1 or length(trim(p_recipient_soop_id)) > 100
    or p_amount < 1 or p_amount > 100000 then
    raise exception 'invalid donation input';
  end if;
  v_points := p_amount * 3;

  perform pg_advisory_xact_lock(hashtext(least(p_sender_soop_id, p_recipient_soop_id)));
  if p_sender_soop_id <> p_recipient_soop_id then
    perform pg_advisory_xact_lock(hashtext(greatest(p_sender_soop_id, p_recipient_soop_id)));
  end if;

  insert into public.gacha_soop_donation_events(event_id, sender_soop_id, recipient_soop_id, amount)
  values (p_event_id, p_sender_soop_id, p_recipient_soop_id, p_amount)
  on conflict (event_id) do nothing
  returning event_id into v_inserted;
  if v_inserted is null then
    return query select false;
    return;
  end if;

  select id into v_sender_user from public.gacha_users where soop_id = p_sender_soop_id for update;
  v_sender_exists := found;
  if v_sender_exists then
    update public.gacha_users set points = public.gacha_users.points + v_points where id = v_sender_user;
  end if;

  if p_recipient_soop_id = p_sender_soop_id then
    if v_sender_exists then
      update public.gacha_users set points = public.gacha_users.points + v_points where id = v_sender_user;
    end if;
  else
    select id into v_recipient_user from public.gacha_users where soop_id = p_recipient_soop_id for update;
    if found then
      update public.gacha_users set points = public.gacha_users.points + v_points where id = v_recipient_user;
    end if;
  end if;

  return query select true;
end;
$$;

revoke all on function public.gacha_apply_soop_donation(text, text, text, integer) from public;
grant execute on function public.gacha_apply_soop_donation(text, text, text, integer) to service_role;
