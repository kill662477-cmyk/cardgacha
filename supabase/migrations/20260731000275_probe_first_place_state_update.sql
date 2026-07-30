-- Diagnose the first-place bulk state update without retaining any player
-- mutation. Each probe runs inside a subtransaction and is forced to roll back.

create table if not exists public.gacha_s2_first_place_reward_diagnostic (
  id integer primary key default 1 check (id = 1),
  status text not null,
  sqlstate text,
  error_message text,
  error_detail text,
  error_hint text,
  error_context text,
  error_schema text,
  error_table text,
  error_column text,
  error_constraint text,
  checked_rows integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.gacha_s2_first_place_reward_diagnostic
  enable row level security;
revoke all on table public.gacha_s2_first_place_reward_diagnostic
  from public, anon, authenticated;
grant select, insert, update, delete
  on table public.gacha_s2_first_place_reward_diagnostic
  to service_role;

truncate table public.gacha_s2_first_place_reward_diagnostic;

do $probe$
declare
  v_target record;
  v_checked integer := 0;
  v_sqlstate text;
  v_message text;
  v_detail text;
  v_hint text;
  v_context text;
  v_schema text;
  v_table text;
  v_column text;
  v_constraint text;
begin
  for v_target in
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
              or lower(trim(donation.sender_soop_id)) =
                lower(trim(account.soop_id))
          )
        then 100000
        else 50000
      end as points_granted,
      1 as ss_selector_granted,
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
              or lower(trim(donation.sender_soop_id)) =
                lower(trim(account.soop_id))
          )
        then 1
        else 0
      end as sss_selector_granted
    from public.gacha_s2_accounts account
    join public.gacha_s2_player_states state
      on state.user_id = account.id
    order by state.user_id
  loop
    begin
      update public.gacha_s2_player_states state
      set points = state.points + v_target.points_granted,
          support_items = jsonb_set(
            jsonb_set(
              state.support_items,
              '{ssCardSelector}',
              to_jsonb(
                coalesce(
                  (state.support_items->>'ssCardSelector')::integer,
                  0
                ) + v_target.ss_selector_granted
              ),
              true
            ),
            '{sssCardSelector}',
            to_jsonb(
              coalesce(
                (state.support_items->>'sssCardSelector')::integer,
                0
              ) + v_target.sss_selector_granted
            ),
            true
          ),
          revision = state.revision + 1,
          updated_at = now()
      where state.user_id = v_target.user_id;

      raise exception using
        errcode = 'ZX001',
        message = 'forced probe rollback';
    exception
      when sqlstate 'ZX001' then
        null;
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
          'FAILED',
          v_sqlstate,
          v_message,
          v_detail,
          v_hint,
          v_context,
          v_schema,
          v_table,
          v_column,
          v_constraint,
          v_checked
        );
        return;
    end;

    v_checked := v_checked + 1;
  end loop;

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
    'ALL_ROWS_OK',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    v_checked
  );
end
$probe$;
