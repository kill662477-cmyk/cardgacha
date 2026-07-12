-- Supabase safe-update environments require an explicit WHERE clause for the all-account grant.
create or replace function public.gacha_grant_all_points(p_amount integer)
returns table(updated_count integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated integer;
begin
  if p_amount < 1 or p_amount > 100000 then
    raise exception 'invalid grant amount';
  end if;

  update public.gacha_users
  set points = public.gacha_users.points + p_amount
  where public.gacha_users.id is not null;
  get diagnostics v_updated = row_count;
  return query select v_updated;
end;
$$;

revoke all on function public.gacha_grant_all_points(integer) from public;
grant execute on function public.gacha_grant_all_points(integer) to service_role;
