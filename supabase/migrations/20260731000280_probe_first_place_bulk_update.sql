-- Diagnose the exact first-place bulk state update without retaining player
-- mutations. The update runs inside a subtransaction and is forced to roll back.

lock table public.gacha_s2_accounts in share mode;
lock table public.gacha_s2_player_states in share row exclusive mode;
lock table public.gacha_s2_soop_post_202512799_rewards in share mode;
lock table public.gacha_s2_soop_donation_events in share mode;

create temporary table soop_first_place_bulk_probe (
  user_id uuid primary key,
  points_granted integer not null,
  ss_selector_granted integer not null,
  sss_selector_granted integer not null
) on commit drop;

insert into soop_first_place_bulk_probe (
  user_id,
  points_granted,
  ss_selector_granted,
  sss_selector_granted
)
select
  state.user_id,
  case
    when exists (
      select 1
      from public.gacha_s2_soop_post_202512799_rewards authenticated
      where authenticated.user_id = account.id
        and authenticated.source_post_id = 202512799
    )
      or account.is_streamer
      or exists (
        select 1
        from public.gacha_s2_soop_donation_events donation
        where donation.sender_user_id = account.id
          or lower(trim(donation.sender_soop_id)) = lower(trim(account.soop_id))
      )
    then 100000
    else 50000
  end,
  1,
  case
    when exists (
      select 1
      from public.gacha_s2_soop_post_202512799_rewards authenticated
      where authenticated.user_id = account.id
        and authenticated.source_post_id = 202512799
    )
      or account.is_streamer
      or exists (
        select 1
        from public.gacha_s2_soop_donation_events donation
        where donation.sender_user_id = account.id
          or lower(trim(donation.sender_soop_id)) = lower(trim(account.soop_id))
      )
    then 1
    else 0
  end
from public.gacha_s2_accounts account
join public.gacha_s2_player_states state
  on state.user_id = account.id;

truncate table public.gacha_s2_first_place_reward_diagnostic;

do $probe$
declare
  v_sqlstate text;
  v_message text;
  v_detail text;
  v_hint text;
  v_context text;
  v_schema text;
  v_table text;
  v_column text;
  v_constraint text;
  v_target_count integer;
begin
  select count(*)
  into v_target_count
  from soop_first_place_bulk_probe;

  begin
    update public.gacha_s2_player_states state
    set points = state.points + probe.points_granted,
        support_items = jsonb_set(
          jsonb_set(
            state.support_items,
            '{ssCardSelector}',
            to_jsonb(
              coalesce(
                (state.support_items->>'ssCardSelector')::integer,
                0
              ) + probe.ss_selector_granted
            ),
            true
          ),
          '{sssCardSelector}',
          to_jsonb(
            coalesce(
              (state.support_items->>'sssCardSelector')::integer,
              0
            ) + probe.sss_selector_granted
          ),
          true
        ),
        revision = state.revision + 1,
        updated_at = now()
    from soop_first_place_bulk_probe probe
    where state.user_id = probe.user_id;

    raise exception using
      errcode = 'ZX002',
      message = 'forced bulk probe rollback';
  exception
    when sqlstate 'ZX002' then
      insert into public.gacha_s2_first_place_reward_diagnostic (
        status,
        checked_rows
      )
      values ('BULK_UPDATE_OK', v_target_count);
    when others then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_message = message_text,
        v_detail = pg_exception_detail,
        v_hint = pg_exception_hint,
        v_context = pg_exception_context,
        v_schema = schema_name,
        v_table = table_name,
        v_column = column_name,
        v_constraint = constraint_name;

      insert into public.gacha_s2_first_place_reward_diagnostic (
        status,
        sqlstate,
        error_message,
        error_detail,
        error_hint,
        error_context,
        error_schema,
        error_table,
        error_column,
        error_constraint,
        checked_rows
      )
      values (
        'BULK_UPDATE_FAILED',
        v_sqlstate,
        v_message,
        v_detail,
        v_hint,
        v_context,
        v_schema,
        v_table,
        v_column,
        v_constraint,
        v_target_count
      );
  end;
end
$probe$;
