create extension if not exists pg_cron;

create or replace function public.gacha_s2_retention_sweep(
  p_batch integer default 20000
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_idempotency integer := 0;
  v_pack_draws integer := 0;
begin
  if p_batch is null or p_batch < 1000 or p_batch > 50000 then
    p_batch := 20000;
  end if;

  with doomed as (
    select ctid from public.gacha_s2_idempotency
    where expires_at < now() - interval '1 hour'
    limit p_batch
  )
  delete from public.gacha_s2_idempotency t using doomed where t.ctid = doomed.ctid;
  get diagnostics v_idempotency = row_count;

  with doomed as (
    select ctid from public.gacha_s2_pack_draws
    where created_at < now() - interval '3 days'
    limit p_batch
  )
  delete from public.gacha_s2_pack_draws t using doomed where t.ctid = doomed.ctid;
  get diagnostics v_pack_draws = row_count;

  return jsonb_build_object(
    'idempotencyDeleted', v_idempotency,
    'packDrawsDeleted', v_pack_draws,
    'batch', p_batch,
    'at', now()
  );
end;
$$;

revoke all on function public.gacha_s2_retention_sweep(integer) from public, anon, authenticated;;
