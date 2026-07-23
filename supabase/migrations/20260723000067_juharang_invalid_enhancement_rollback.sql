-- Roll back enhancement attempts that used the temporarily inflated SS Juharang 3/4 copies.
-- Migration 066 already returned those Juharang materials at their original rarities.

begin;

lock table public.gacha_s2_player_cards,
  public.gacha_s2_player_states,
  public.gacha_s2_collection_records,
  public.gacha_s2_enhancement_results,
  public.gacha_s2_idempotency
in share row exclusive mode;

create table if not exists public.gacha_s2_juharang_invalid_enhancement_attempts_20260723 (
  source_result_id bigint primary key references public.gacha_s2_enhancement_results(id),
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  command_id text not null,
  card_id text not null,
  from_enhancement integer not null,
  final_enhancement integer not null,
  outcome text not null,
  materials jsonb not null,
  points_spent integer not null,
  booster_id text,
  attempted_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

with refresh_cutoff as (
  select updated_at
  from public.gacha_s2_card_catalog
  where card_id = 'juharang-3'
)
insert into public.gacha_s2_juharang_invalid_enhancement_attempts_20260723 (
  source_result_id,
  user_id,
  command_id,
  card_id,
  from_enhancement,
  final_enhancement,
  outcome,
  materials,
  points_spent,
  booster_id,
  attempted_at
)
select
  result.id,
  result.user_id,
  result.command_id,
  result.card_id,
  result.from_enhancement,
  result.final_enhancement,
  result.outcome,
  result.materials,
  result.points_spent,
  result.booster_id,
  result.created_at
from public.gacha_s2_enhancement_results result
cross join refresh_cutoff cutoff
where result.created_at >= cutoff.updated_at
  and result.materials ?| array['juharang-3', 'juharang-4']
on conflict (source_result_id) do nothing;

create table if not exists public.gacha_s2_juharang_enhancement_rollback_20260723 (
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  card_id text not null,
  enhancement_before integer not null,
  card_exp_before integer not null,
  rollback_enhancement integer not null,
  rollback_card_exp integer not null,
  attempts_rolled_back integer not null,
  successes_rolled_back integer not null,
  points_refunded integer not null,
  enhance5_refunded integer not null,
  enhance10_refunded integer not null,
  destruction_guard_refunded integer not null,
  exp_potions_refunded integer not null,
  enhancement_after integer,
  card_exp_after integer,
  rolled_back_at timestamptz not null default now(),
  primary key (user_id, card_id)
);

with active_config as (
  select config,
    coalesce((config->'supportItems'->'cardExpPotionLarge'->>'cardExp')::integer, 20) as potion_exp
  from public.gacha_s2_balance_versions
  where active
),
grouped as (
  select
    attempt.user_id,
    attempt.card_id,
    (array_agg(attempt.from_enhancement order by attempt.attempted_at, attempt.source_result_id))[1] as rollback_enhancement,
    count(*)::integer as attempts_rolled_back,
    count(*) filter (where attempt.outcome = 'success')::integer as successes_rolled_back,
    sum(attempt.points_spent)::integer as points_refunded,
    count(*) filter (where attempt.booster_id = 'enhance5')::integer as enhance5_refunded,
    count(*) filter (where attempt.booster_id = 'enhance10')::integer as enhance10_refunded,
    count(*) filter (where attempt.booster_id = 'destructionGuard')::integer as destruction_guard_refunded,
    sum(
      case when attempt.outcome = 'success'
        then (active.config->'enhancement'->'expRequirements'->>attempt.from_enhancement)::integer
        else 0
      end
    )::integer as success_exp_consumed,
    active.config,
    active.potion_exp
  from public.gacha_s2_juharang_invalid_enhancement_attempts_20260723 attempt
  cross join active_config active
  group by attempt.user_id, attempt.card_id, active.config, active.potion_exp
)
insert into public.gacha_s2_juharang_enhancement_rollback_20260723 (
  user_id,
  card_id,
  enhancement_before,
  card_exp_before,
  rollback_enhancement,
  rollback_card_exp,
  attempts_rolled_back,
  successes_rolled_back,
  points_refunded,
  enhance5_refunded,
  enhance10_refunded,
  destruction_guard_refunded,
  exp_potions_refunded
)
select
  grouped.user_id,
  grouped.card_id,
  owned.enhancement,
  owned.card_exp,
  grouped.rollback_enhancement,
  (grouped.config->'enhancement'->'expRequirements'->>grouped.rollback_enhancement)::integer,
  grouped.attempts_rolled_back,
  grouped.successes_rolled_back,
  grouped.points_refunded,
  grouped.enhance5_refunded,
  grouped.enhance10_refunded,
  grouped.destruction_guard_refunded,
  ceil(greatest(
    0,
    grouped.success_exp_consumed
      - (grouped.config->'enhancement'->'expRequirements'->>grouped.rollback_enhancement)::integer
      + owned.card_exp
  )::numeric / grouped.potion_exp)::integer
from grouped
join public.gacha_s2_player_cards owned
  on owned.user_id = grouped.user_id
 and owned.card_id = grouped.card_id
on conflict (user_id, card_id) do nothing;

do $$
begin
  if exists (
    with first_affected as (
      select distinct on (user_id, card_id)
        user_id, card_id, attempted_at, source_result_id
      from public.gacha_s2_juharang_invalid_enhancement_attempts_20260723
      order by user_id, card_id, attempted_at, source_result_id
    )
    select 1
    from first_affected first
    join public.gacha_s2_enhancement_results result
      on result.user_id = first.user_id
     and result.card_id = first.card_id
     and (result.created_at, result.id) >= (first.attempted_at, first.source_result_id)
    left join public.gacha_s2_juharang_invalid_enhancement_attempts_20260723 affected
      on affected.source_result_id = result.id
    where affected.source_result_id is null
  ) then
    raise exception 'A later valid enhancement depends on an invalid Juharang attempt';
  end if;

  if exists (
    with last_affected as (
      select distinct on (user_id, card_id)
        user_id, card_id, final_enhancement
      from public.gacha_s2_juharang_invalid_enhancement_attempts_20260723
      order by user_id, card_id, attempted_at desc, source_result_id desc
    )
    select 1
    from last_affected last
    join public.gacha_s2_player_cards owned
      on owned.user_id = last.user_id
     and owned.card_id = last.card_id
    where owned.enhancement <> last.final_enhancement
  ) then
    raise exception 'Current enhancement no longer matches the affected attempt chain';
  end if;

  if (
    select coalesce(sum(material_count), 0)
    from (
      select count(*)::integer as material_count
      from public.gacha_s2_juharang_invalid_enhancement_attempts_20260723 attempt
      cross join lateral jsonb_array_elements_text(attempt.materials) material(card_id)
      where material.card_id in ('juharang-3', 'juharang-4')
    ) counted
  ) <> (
    select coalesce(sum(enhancement_materials_refunded), 0)
    from public.gacha_s2_juharang_duplicate_recovery_20260723
  ) then
    raise exception 'Previously refunded Juharang enhancement material count mismatch';
  end if;
end;
$$;

with other_materials as (
  select attempt.user_id, material.card_id, count(*)::integer as copies
  from public.gacha_s2_juharang_invalid_enhancement_attempts_20260723 attempt
  cross join lateral jsonb_array_elements_text(attempt.materials) material(card_id)
  where material.card_id not in ('juharang-3', 'juharang-4')
  group by attempt.user_id, material.card_id
)
insert into public.gacha_s2_player_cards (user_id, card_id, copies, enhancement, card_exp, locked)
select user_id, card_id, copies, 0, 0, false
from other_materials
on conflict (user_id, card_id) do update
set copies = public.gacha_s2_player_cards.copies + excluded.copies,
    updated_at = now();

with other_materials as (
  select distinct attempt.user_id, material.card_id
  from public.gacha_s2_juharang_invalid_enhancement_attempts_20260723 attempt
  cross join lateral jsonb_array_elements_text(attempt.materials) material(card_id)
  where material.card_id not in ('juharang-3', 'juharang-4')
)
insert into public.gacha_s2_collection_records (user_id, card_id)
select user_id, card_id
from other_materials
on conflict (user_id, card_id) do nothing;

update public.gacha_s2_player_cards owned
set enhancement = rollback.rollback_enhancement,
    card_exp = rollback.rollback_card_exp,
    updated_at = now()
from public.gacha_s2_juharang_enhancement_rollback_20260723 rollback
where owned.user_id = rollback.user_id
  and owned.card_id = rollback.card_id;

with per_user as (
  select
    user_id,
    sum(attempts_rolled_back)::integer as attempts_rolled_back,
    sum(points_refunded)::integer as points_refunded,
    sum(enhance5_refunded)::integer as enhance5_refunded,
    sum(enhance10_refunded)::integer as enhance10_refunded,
    sum(destruction_guard_refunded)::integer as destruction_guard_refunded,
    sum(exp_potions_refunded)::integer as exp_potions_refunded
  from public.gacha_s2_juharang_enhancement_rollback_20260723
  group by user_id
)
update public.gacha_s2_player_states state
set points = state.points + refund.points_refunded,
    support_items = jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            state.support_items,
            '{enhance5}',
            to_jsonb(coalesce((state.support_items->>'enhance5')::integer, 0) + refund.enhance5_refunded),
            true
          ),
          '{enhance10}',
          to_jsonb(coalesce((state.support_items->>'enhance10')::integer, 0) + refund.enhance10_refunded),
          true
        ),
        '{destructionGuard}',
        to_jsonb(coalesce((state.support_items->>'destructionGuard')::integer, 0) + refund.destruction_guard_refunded),
        true
      ),
      '{cardExpPotionLarge}',
      to_jsonb(coalesce((state.support_items->>'cardExpPotionLarge')::integer, 0) + refund.exp_potions_refunded),
      true
    ),
    enhancement_attempts = greatest(0, state.enhancement_attempts - refund.attempts_rolled_back),
    revision = state.revision + 1,
    updated_at = now()
from per_user refund
where state.user_id = refund.user_id;

update public.gacha_s2_juharang_enhancement_rollback_20260723 rollback
set enhancement_after = owned.enhancement,
    card_exp_after = owned.card_exp
from public.gacha_s2_player_cards owned
where owned.user_id = rollback.user_id
  and owned.card_id = rollback.card_id;

update public.gacha_s2_idempotency replay
set response = public.gacha_s2_command_error(
      replay.idempotency_key,
      'VERSION_CONFLICT',
      '관리자 복구가 적용되어 최신 기록을 다시 불러와야 합니다.',
      state.revision,
      public.gacha_s2_get_player_snapshot(state.user_id),
      jsonb_build_object('reason', 'JUHARANG_INVALID_MATERIAL_ROLLBACK')
    ),
    expires_at = greatest(replay.expires_at, now() + interval '24 hours')
from public.gacha_s2_juharang_invalid_enhancement_attempts_20260723 attempt
join public.gacha_s2_player_states state on state.user_id = attempt.user_id
where replay.user_id = attempt.user_id
  and replay.idempotency_key = attempt.command_id;

do $$
begin
  if exists (
    select 1
    from public.gacha_s2_juharang_enhancement_rollback_20260723 rollback
    where rollback.enhancement_after <> rollback.rollback_enhancement
       or rollback.card_exp_after <> rollback.rollback_card_exp
  ) then
    raise exception 'Juharang invalid enhancement rollback validation failed';
  end if;
end;
$$;

revoke all on table public.gacha_s2_juharang_invalid_enhancement_attempts_20260723
  from public, anon, authenticated;
revoke all on table public.gacha_s2_juharang_enhancement_rollback_20260723
  from public, anon, authenticated;

commit;
