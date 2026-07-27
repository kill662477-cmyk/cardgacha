-- Lotto minigame: three KST draws per day, one ticket per account and round.
-- Lotto purchases and payouts are deliberately separate from minigame daily reward caps.

create extension if not exists pg_cron;
create extension if not exists pgcrypto;

create or replace function public.gacha_s2_lotto_numbers_valid(p_numbers integer[])
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select p_numbers is not null
    and cardinality(p_numbers) = 6
    and (select count(distinct value) from unnest(p_numbers) as picked(value)) = 6
    and (select min(value) >= 1 and max(value) <= 18 from unnest(p_numbers) as picked(value));
$$;

create or replace function public.gacha_s2_lotto_next_draw(p_now timestamptz default now())
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_local timestamp := p_now at time zone 'Asia/Seoul';
  v_day date := (p_now at time zone 'Asia/Seoul')::date;
  v_time time := (p_now at time zone 'Asia/Seoul')::time;
  v_draw_local timestamp;
begin
  if v_time < time '10:00' then
    v_draw_local := v_day + time '10:00';
  elsif v_time < time '15:00' then
    v_draw_local := v_day + time '15:00';
  elsif v_time < time '20:00' then
    v_draw_local := v_day + time '20:00';
  else
    v_draw_local := (v_day + 1) + time '10:00';
  end if;
  return v_draw_local at time zone 'Asia/Seoul';
end;
$$;

create table if not exists public.gacha_s2_lotto_rounds (
  round_id text primary key check (round_id ~ '^[0-9]{8}-(10|15|20)00$'),
  draw_at timestamptz not null unique,
  sales_close_at timestamptz not null,
  status text not null default 'open' check (status in ('open', 'drawn')),
  first_pool bigint not null check (first_pool between 100000 and 500000),
  second_pool bigint not null check (second_pool between 50000 and 500000),
  winning_numbers integer[],
  first_winners integer not null default 0 check (first_winners >= 0),
  second_winners integer not null default 0 check (second_winners >= 0),
  third_winners integer not null default 0 check (third_winners >= 0),
  fourth_winners integer not null default 0 check (fourth_winners >= 0),
  first_carry_out bigint not null default 0 check (first_carry_out between 0 and 500000),
  second_carry_out bigint not null default 0 check (second_carry_out between 0 and 500000),
  ticket_count integer not null default 0 check (ticket_count >= 0),
  sales_points bigint not null default 0 check (sales_points >= 0),
  payout_points bigint not null default 0 check (payout_points >= 0),
  drawn_at timestamptz,
  created_at timestamptz not null default now(),
  check (sales_close_at = draw_at - interval '10 minutes'),
  check (
    (status = 'open' and winning_numbers is null and drawn_at is null)
    or (
      status = 'drawn'
      and public.gacha_s2_lotto_numbers_valid(winning_numbers)
      and drawn_at is not null
    )
  )
);

create table if not exists public.gacha_s2_lotto_tickets (
  ticket_id uuid primary key default gen_random_uuid(),
  round_id text not null references public.gacha_s2_lotto_rounds(round_id) on delete restrict,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  numbers integer[] not null check (public.gacha_s2_lotto_numbers_valid(numbers)),
  cost_points integer not null default 1000 check (cost_points = 1000),
  match_count integer check (match_count is null or match_count between 0 and 6),
  rank integer check (rank is null or rank between 1 and 4),
  prize_points bigint not null default 0 check (prize_points >= 0),
  paid_at timestamptz,
  purchased_at timestamptz not null default now(),
  unique (round_id, user_id)
);

create index if not exists idx_gacha_s2_lotto_tickets_round
  on public.gacha_s2_lotto_tickets(round_id, rank);
create index if not exists idx_gacha_s2_lotto_tickets_user
  on public.gacha_s2_lotto_tickets(user_id, purchased_at desc);

create table if not exists public.gacha_s2_lotto_payouts (
  payout_id bigint generated always as identity primary key,
  round_id text not null references public.gacha_s2_lotto_rounds(round_id) on delete restrict,
  ticket_id uuid not null references public.gacha_s2_lotto_tickets(ticket_id) on delete restrict,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  rank integer not null check (rank between 1 and 4),
  points bigint not null check (points > 0),
  created_at timestamptz not null default now(),
  unique (round_id, user_id),
  unique (ticket_id)
);

create index if not exists idx_gacha_s2_lotto_payouts_recent
  on public.gacha_s2_lotto_payouts(created_at desc);

alter table public.gacha_s2_lotto_rounds enable row level security;
alter table public.gacha_s2_lotto_tickets enable row level security;
alter table public.gacha_s2_lotto_payouts enable row level security;

revoke all on table public.gacha_s2_lotto_rounds from public, anon, authenticated;
revoke all on table public.gacha_s2_lotto_tickets from public, anon, authenticated;
revoke all on table public.gacha_s2_lotto_payouts from public, anon, authenticated;

create or replace function public.gacha_s2_lotto_ensure_round(p_draw_at timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_round_id text := to_char(p_draw_at at time zone 'Asia/Seoul', 'YYYYMMDD-HH24MI');
  v_first_carry bigint := 0;
  v_second_carry bigint := 0;
begin
  if extract(minute from p_draw_at at time zone 'Asia/Seoul') <> 0
    or extract(hour from p_draw_at at time zone 'Asia/Seoul') not in (10, 15, 20) then
    raise exception 'invalid lotto draw slot';
  end if;

  if exists (select 1 from public.gacha_s2_lotto_rounds where round_id = v_round_id) then
    return v_round_id;
  end if;

  select first_carry_out, second_carry_out
  into v_first_carry, v_second_carry
  from public.gacha_s2_lotto_rounds
  where status = 'drawn' and draw_at < p_draw_at
  order by draw_at desc
  limit 1;

  insert into public.gacha_s2_lotto_rounds (
    round_id, draw_at, sales_close_at, first_pool, second_pool
  ) values (
    v_round_id,
    p_draw_at,
    p_draw_at - interval '10 minutes',
    least(500000::bigint, 100000 + coalesce(v_first_carry, 0)),
    least(500000::bigint, 50000 + coalesce(v_second_carry, 0))
  )
  on conflict (round_id) do nothing;

  return v_round_id;
end;
$$;

-- Allow lotto winner events in the existing public ticker without exposing account IDs.
alter table public.gacha_s2_live_events
  drop constraint if exists gacha_s2_live_events_event_type_check;
alter table public.gacha_s2_live_events
  drop constraint if exists gacha_s2_live_events_check;
alter table public.gacha_s2_live_events
  drop constraint if exists gacha_s2_live_events_event_type_v2_check;
alter table public.gacha_s2_live_events
  drop constraint if exists gacha_s2_live_events_payload_v2_check;
alter table public.gacha_s2_live_events
  alter column card_id drop not null,
  alter column member drop not null,
  alter column rarity drop not null;
alter table public.gacha_s2_live_events
  add column if not exists event_rank integer,
  add column if not exists points bigint,
  add column if not exists lotto_round_id text;
alter table public.gacha_s2_live_events
  add constraint gacha_s2_live_events_event_type_v2_check
  check (event_type in ('card_draw', 'nine_star_success', 'lotto_first', 'lotto_second'));
alter table public.gacha_s2_live_events
  add constraint gacha_s2_live_events_payload_v2_check
  check (
    (
      event_type = 'card_draw'
      and card_id is not null and member is not null
      and rarity in ('S', 'SS', 'SSS') and enhancement is null
      and event_rank is null and points is null and lotto_round_id is null
    )
    or (
      event_type = 'nine_star_success'
      and card_id is not null and member is not null and rarity is not null
      and enhancement = 9
      and event_rank is null and points is null and lotto_round_id is null
    )
    or (
      event_type in ('lotto_first', 'lotto_second')
      and card_id is null and member is null and rarity is null and enhancement is null
      and event_rank = case event_type when 'lotto_first' then 1 else 2 end
      and points > 0 and lotto_round_id is not null
    )
  );

create or replace function public.gacha_s2_lotto_settle_due(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_round public.gacha_s2_lotto_rounds%rowtype;
  v_winning integer[];
  v_first_winners integer;
  v_second_winners integer;
  v_third_winners integer;
  v_fourth_winners integer;
  v_first_each bigint;
  v_second_each bigint;
  v_first_carry bigint;
  v_second_carry bigint;
  v_payout bigint;
  v_settled integer := 0;
begin
  perform pg_advisory_xact_lock(hashtext('gacha_s2_lotto_settlement'));

  for v_round in
    select *
    from public.gacha_s2_lotto_rounds
    where status = 'open' and draw_at <= p_now
    order by draw_at
    for update
  loop
    select array_agg(value order by value)
    into v_winning
    from (
      select value
      from generate_series(1, 18) as candidates(value)
      order by encode(gen_random_bytes(16), 'hex')
      limit 6
    ) drawn;

    with scored as (
      select
        ticket_id,
        (
          select count(*)::integer
          from unnest(ticket.numbers) as picked(value)
          where value = any(v_winning)
        ) as matches
      from public.gacha_s2_lotto_tickets ticket
      where ticket.round_id = v_round.round_id
    )
    update public.gacha_s2_lotto_tickets ticket
    set match_count = scored.matches,
        rank = case scored.matches
          when 6 then 1
          when 5 then 2
          when 4 then 3
          when 3 then 4
          else null
        end
    from scored
    where ticket.ticket_id = scored.ticket_id;

    select
      count(*) filter (where rank = 1),
      count(*) filter (where rank = 2),
      count(*) filter (where rank = 3),
      count(*) filter (where rank = 4)
    into v_first_winners, v_second_winners, v_third_winners, v_fourth_winners
    from public.gacha_s2_lotto_tickets
    where round_id = v_round.round_id;

    v_first_each := case when v_first_winners > 0 then v_round.first_pool / v_first_winners else 0 end;
    v_second_each := case when v_second_winners > 0 then v_round.second_pool / v_second_winners else 0 end;
    v_first_carry := case when v_first_winners > 0
      then v_round.first_pool - (v_first_each * v_first_winners)
      else v_round.first_pool end;
    v_second_carry := case when v_second_winners > 0
      then v_round.second_pool - (v_second_each * v_second_winners)
      else v_round.second_pool end;

    update public.gacha_s2_lotto_tickets
    set prize_points = case rank
      when 1 then v_first_each
      when 2 then v_second_each
      when 3 then 2000
      when 4 then 1000
      else 0
    end
    where round_id = v_round.round_id;

    with inserted as (
      insert into public.gacha_s2_lotto_payouts (
        round_id, ticket_id, user_id, rank, points
      )
      select round_id, ticket_id, user_id, rank, prize_points
      from public.gacha_s2_lotto_tickets
      where round_id = v_round.round_id and rank between 1 and 4 and prize_points > 0
      on conflict (round_id, user_id) do nothing
      returning user_id, points
    )
    update public.gacha_s2_player_states state
    set points = state.points + inserted.points,
        revision = state.revision + 1,
        updated_at = now()
    from inserted
    where state.user_id = inserted.user_id;

    update public.gacha_s2_lotto_tickets ticket
    set paid_at = payout.created_at
    from public.gacha_s2_lotto_payouts payout
    where ticket.ticket_id = payout.ticket_id
      and ticket.round_id = v_round.round_id;

    insert into public.gacha_s2_live_events (
      source_key, event_type, nickname, card_id, member, rarity, enhancement,
      event_rank, points, lotto_round_id, created_at
    )
    select
      encode(digest(
        'lotto:' || payout.round_id || ':' || payout.user_id::text || ':' || payout.rank::text,
        'sha256'
      ), 'hex'),
      case payout.rank when 1 then 'lotto_first' else 'lotto_second' end,
      account.nickname,
      null, null, null, null,
      payout.rank,
      payout.points,
      payout.round_id,
      payout.created_at
    from public.gacha_s2_lotto_payouts payout
    join public.gacha_s2_accounts account on account.id = payout.user_id
    where payout.round_id = v_round.round_id and payout.rank in (1, 2)
    on conflict (source_key) do nothing;

    select coalesce(sum(points), 0)
    into v_payout
    from public.gacha_s2_lotto_payouts
    where round_id = v_round.round_id;

    update public.gacha_s2_lotto_rounds
    set status = 'drawn',
        winning_numbers = v_winning,
        first_winners = v_first_winners,
        second_winners = v_second_winners,
        third_winners = v_third_winners,
        fourth_winners = v_fourth_winners,
        first_carry_out = v_first_carry,
        second_carry_out = v_second_carry,
        payout_points = v_payout,
        drawn_at = p_now
    where round_id = v_round.round_id;

    v_settled := v_settled + 1;
  end loop;

  return jsonb_build_object('settled', v_settled, 'at', p_now);
end;
$$;

create or replace function public.gacha_s2_lotto_cron_draw()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
  v_due_draw timestamptz := public.gacha_s2_lotto_next_draw(now() - interval '1 minute');
  v_result jsonb;
begin
  -- Cron runs at 10:00, 15:00 and 20:00 KST. The one-minute lookback resolves
  -- the slot that just closed even if pg_cron starts a few seconds late.
  if v_due_draw <= v_now and v_now - v_due_draw < interval '5 minutes' then
    perform public.gacha_s2_lotto_ensure_round(v_due_draw);
  end if;
  v_result := public.gacha_s2_lotto_settle_due(v_now);
  perform public.gacha_s2_lotto_ensure_round(public.gacha_s2_lotto_next_draw(v_now));
  return v_result;
end;
$$;

create or replace function public.gacha_s2_get_lotto_state(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
  v_draw_at timestamptz;
  v_round_id text;
  v_round public.gacha_s2_lotto_rounds%rowtype;
  v_ticket jsonb;
  v_revision bigint;
  v_points integer;
begin
  if p_user_id is null or not exists (
    select 1 from public.gacha_s2_accounts where id = p_user_id
  ) then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;

  perform public.gacha_s2_lotto_settle_due(v_now);
  v_draw_at := public.gacha_s2_lotto_next_draw(v_now);
  v_round_id := public.gacha_s2_lotto_ensure_round(v_draw_at);
  select * into v_round from public.gacha_s2_lotto_rounds where round_id = v_round_id;
  select revision, points into v_revision, v_points
  from public.gacha_s2_player_states where user_id = p_user_id;

  select jsonb_build_object(
    'numbers', to_jsonb(ticket.numbers),
    'purchasedAt', floor(extract(epoch from ticket.purchased_at) * 1000)::bigint
  )
  into v_ticket
  from public.gacha_s2_lotto_tickets ticket
  where ticket.round_id = v_round_id and ticket.user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'serverTime', public.gacha_s2_now_ms(),
    'playerRevision', v_revision,
    'playerPoints', v_points,
    'round', jsonb_build_object(
      'roundId', v_round.round_id,
      'drawAt', floor(extract(epoch from v_round.draw_at) * 1000)::bigint,
      'salesCloseAt', floor(extract(epoch from v_round.sales_close_at) * 1000)::bigint,
      'saleOpen', v_now < v_round.sales_close_at and v_round.status = 'open',
      'firstPool', v_round.first_pool,
      'secondPool', v_round.second_pool,
      'ticketCount', v_round.ticket_count
    ),
    'ticket', v_ticket,
    'recentResults', coalesce((
      select jsonb_agg(result.payload order by result.draw_at desc)
      from (
        select round.draw_at, jsonb_build_object(
          'roundId', round.round_id,
          'drawAt', floor(extract(epoch from round.draw_at) * 1000)::bigint,
          'winningNumbers', to_jsonb(round.winning_numbers),
          'firstWinners', round.first_winners,
          'secondWinners', round.second_winners,
          'thirdWinners', round.third_winners,
          'fourthWinners', round.fourth_winners,
          'firstCarryOut', round.first_carry_out,
          'secondCarryOut', round.second_carry_out
        ) payload
        from public.gacha_s2_lotto_rounds round
        where round.status = 'drawn'
        order by round.draw_at desc
        limit 5
      ) result
    ), '[]'::jsonb),
    'myRecentTickets', coalesce((
      select jsonb_agg(result.payload order by result.draw_at desc)
      from (
        select round.draw_at, jsonb_build_object(
          'roundId', ticket.round_id,
          'drawAt', floor(extract(epoch from round.draw_at) * 1000)::bigint,
          'numbers', to_jsonb(ticket.numbers),
          'winningNumbers', to_jsonb(round.winning_numbers),
          'matchCount', ticket.match_count,
          'rank', ticket.rank,
          'prizePoints', ticket.prize_points,
          'paidAt', case when ticket.paid_at is null then null
            else floor(extract(epoch from ticket.paid_at) * 1000)::bigint end
        ) payload
        from public.gacha_s2_lotto_tickets ticket
        join public.gacha_s2_lotto_rounds round on round.round_id = ticket.round_id
        where ticket.user_id = p_user_id and round.status = 'drawn'
        order by round.draw_at desc
        limit 5
      ) result
    ), '[]'::jsonb),
    'recentWinners', coalesce((
      select jsonb_agg(winner.payload order by winner.created_at desc)
      from (
        select payout.created_at, jsonb_build_object(
          'roundId', payout.round_id,
          'nickname', account.nickname,
          'rank', payout.rank,
          'points', payout.points,
          'createdAt', floor(extract(epoch from payout.created_at) * 1000)::bigint
        ) payload
        from public.gacha_s2_lotto_payouts payout
        join public.gacha_s2_accounts account on account.id = payout.user_id
        where payout.rank in (1, 2)
        order by payout.created_at desc
        limit 20
      ) winner
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.gacha_s2_buy_lotto_ticket(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_numbers integer[]
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
  v_draw_at timestamptz;
  v_round_id text;
  v_revision bigint;
  v_points integer;
  v_numbers integer[];
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or not public.gacha_s2_lotto_numbers_valid(p_numbers) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '로또 번호 1~18 중 서로 다른 6개를 선택해야 합니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null,
      jsonb_build_object('field', 'numbers')
    );
  end if;

  select array_agg(value order by value) into v_numbers
  from unnest(p_numbers) as picked(value);
  perform public.gacha_s2_lotto_settle_due(v_now);
  v_draw_at := public.gacha_s2_lotto_next_draw(v_now);
  if v_now >= v_draw_at - interval '10 minutes' then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '추첨 10분 전부터는 구매할 수 없습니다.',
      p_expected_revision, null,
      jsonb_build_object('drawAt', floor(extract(epoch from v_draw_at) * 1000)::bigint)
    );
  end if;
  v_round_id := public.gacha_s2_lotto_ensure_round(v_draw_at);

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'buyLottoTicket',
    'expectedRevision', p_expected_revision,
    'roundId', v_round_id,
    'numbers', to_jsonb(v_numbers)
  )::text, 'sha256'), 'hex');

  select revision, points into v_revision, v_points
  from public.gacha_s2_player_states
  where user_id = p_user_id
  for update;
  if not found then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.',
      0, null, null
    );
  end if;

  select * into v_previous
  from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'buyLottoTicket' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등성 키를 다른 요청에 사용할 수 없습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;

  if p_expected_revision <> v_revision then
    v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와야 합니다.',
      v_revision, v_snapshot, null
    );
  end if;
  if v_points < 1000 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '로또 구매에 1,000P가 필요합니다.',
      v_revision, null, jsonb_build_object('requiredPoints', 1000)
    );
  end if;
  if exists (
    select 1 from public.gacha_s2_lotto_tickets
    where round_id = v_round_id and user_id = p_user_id
  ) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이번 회차 로또는 이미 구매했습니다.',
      v_revision, null, jsonb_build_object('roundId', v_round_id)
    );
  end if;

  insert into public.gacha_s2_lotto_tickets (round_id, user_id, numbers)
  values (v_round_id, p_user_id, v_numbers);

  update public.gacha_s2_lotto_rounds
  set ticket_count = ticket_count + 1,
      sales_points = sales_points + 1000
  where round_id = v_round_id and status = 'open' and sales_close_at > v_now;
  if not found then
    raise exception 'LOTTO_ROUND_CLOSED';
  end if;

  update public.gacha_s2_player_states
  set points = points - 1000,
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id
  returning revision into v_revision;

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1,
    'ok', true,
    'commandId', p_idempotency_key,
    'idempotencyKey', p_idempotency_key,
    'revision', v_revision,
    'serverTime', public.gacha_s2_now_ms(),
    'serverSeed', 0,
    'snapshot', v_snapshot,
    'result', jsonb_build_object(
      'roundId', v_round_id,
      'drawAt', floor(extract(epoch from v_draw_at) * 1000)::bigint,
      'numbers', to_jsonb(v_numbers),
      'costPoints', 1000
    )
  );

  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'buyLottoTicket', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision
  ) values (
    p_user_id, p_idempotency_key, 'buyLottoTicket', v_request_hash, p_expected_revision, v_revision
  );

  return v_response;
end;
$$;

revoke all on function public.gacha_s2_lotto_numbers_valid(integer[]) from public, anon, authenticated;
revoke all on function public.gacha_s2_lotto_next_draw(timestamptz) from public, anon, authenticated;
revoke all on function public.gacha_s2_lotto_ensure_round(timestamptz) from public, anon, authenticated;
revoke all on function public.gacha_s2_lotto_settle_due(timestamptz) from public, anon, authenticated;
revoke all on function public.gacha_s2_lotto_cron_draw() from public, anon, authenticated;
revoke all on function public.gacha_s2_get_lotto_state(uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_buy_lotto_ticket(uuid, bigint, text, integer[]) from public, anon, authenticated;

grant execute on function public.gacha_s2_get_lotto_state(uuid) to service_role;
grant execute on function public.gacha_s2_buy_lotto_ticket(uuid, bigint, text, integer[]) to service_role;

-- Seed the upcoming round so its advertised pools are stable before the first purchase.
select public.gacha_s2_lotto_settle_due(now());
select public.gacha_s2_lotto_ensure_round(public.gacha_s2_lotto_next_draw(now()));

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in select jobid from cron.job where jobname = 'gacha-s2-lotto-draw'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
  perform cron.schedule(
    'gacha-s2-lotto-draw',
    '0 1,6,11 * * *',
    'select public.gacha_s2_lotto_cron_draw();'
  );
end;
$$;
