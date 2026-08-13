-- Correct the 100P floor recovery to lots that demonstrably survived an adverse
-- underlying tick at 100P without reaching their liquidation threshold.

drop trigger if exists gacha_s2_apply_market_floor_outstanding_trigger
  on public.gacha_s2_player_states;

create table if not exists public.gacha_s2_market_floor_recovery_corrections (
  operation_key text not null check (length(operation_key) between 1 and 160),
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  original_recovery_amount bigint not null check (original_recovery_amount >= 0),
  recovered_before_correction bigint not null check (recovered_before_correction >= 0),
  revised_recovery_amount bigint not null check (revised_recovery_amount >= 0),
  refund_points bigint not null check (refund_points >= 0),
  effective_recovered_points bigint not null check (effective_recovered_points >= 0),
  outstanding_points bigint not null check (outstanding_points >= 0),
  points_before integer not null check (points_before >= 0),
  points_after integer not null check (points_after >= 0),
  applied_at timestamptz,
  last_recovered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (operation_key, user_id),
  constraint gacha_s2_market_floor_recovery_corrections_refund_check
    check (refund_points = greatest(0, recovered_before_correction - revised_recovery_amount)),
  constraint gacha_s2_market_floor_recovery_corrections_balance_check
    check (effective_recovered_points + outstanding_points = revised_recovery_amount)
);

create index if not exists gacha_s2_market_floor_recovery_corrections_outstanding_idx
  on public.gacha_s2_market_floor_recovery_corrections(user_id)
  where outstanding_points > 0;

alter table public.gacha_s2_market_floor_recovery_corrections enable row level security;
revoke all on table public.gacha_s2_market_floor_recovery_corrections
  from public, anon, authenticated;
grant select on table public.gacha_s2_market_floor_recovery_corrections to service_role;

lock table public.gacha_s2_player_states in share row exclusive mode;
lock table public.gacha_s2_market_holdings in share row exclusive mode;
lock table public.gacha_s2_market_trades in share row exclusive mode;
lock table public.gacha_s2_market_liquidations in share row exclusive mode;
lock table public.gacha_s2_market_product_prices in share row exclusive mode;
lock table public.gacha_s2_market_prices in share row exclusive mode;

create temporary table market_floor_exact_products on commit drop as
select distinct user_id, symbol, position_type, multiplier
from (
  select user_id, symbol, position_type, multiplier
  from public.gacha_s2_market_trades
  where multiplier >= 2
  union
  select user_id, symbol, position_type, multiplier
  from public.gacha_s2_market_liquidations
) products;

create temporary table market_floor_exact_state (
  user_id uuid not null,
  symbol text not null,
  position_type text not null,
  multiplier smallint not null,
  total_quantity numeric not null default 0,
  total_cost numeric not null default 0,
  entry_underlying_price integer not null default 0,
  previous_underlying_price integer,
  realized_floor_profit numeric not null default 0,
  primary key (user_id, symbol, position_type, multiplier)
) on commit drop;

create temporary table market_floor_exact_lots (
  lot_id bigserial primary key,
  user_id uuid not null,
  symbol text not null,
  position_type text not null,
  multiplier smallint not null,
  remaining_quantity numeric not null,
  remaining_cost numeric not null,
  qualified boolean not null default false
) on commit drop;

create index market_floor_exact_lots_product_idx
  on market_floor_exact_lots(user_id, symbol, position_type, multiplier);

do $calculate$
declare
  v_event record;
  v_state market_floor_exact_state%rowtype;
  v_buy_cost numeric;
  v_buy_underlying integer;
  v_ratio numeric;
  v_qualified_profit numeric;
  v_threshold integer;
  v_liquidated boolean;
  v_adverse boolean;
begin
  for v_event in
    select timeline.*
    from (
      select ('tick:' || product.hour_at::text) as event_id,
             key.user_id,
             key.symbol,
             key.position_type,
             key.multiplier,
             'tick'::text as event_type,
             0::integer as quantity,
             0::integer as unit_price,
             0::bigint as gross_points,
             0::bigint as fee_points,
             0::bigint as net_points,
             0::bigint as removed_cost_basis,
             product.price as product_price,
             underlying.price as underlying_price,
             product.hour_at as event_at,
             0 as event_order
      from market_floor_exact_products key
      join public.gacha_s2_market_product_prices product
        on product.symbol = key.symbol
       and product.position_type = key.position_type
       and product.multiplier = key.multiplier
      join public.gacha_s2_market_prices underlying
        on underlying.symbol = product.symbol
       and underlying.hour_at = product.hour_at

      union all

      select liquidation.liquidation_id::text,
             liquidation.user_id,
             liquidation.symbol,
             liquidation.position_type,
             liquidation.multiplier,
             'liquidation',
             liquidation.quantity,
             0,
             0,
             0,
             0,
             liquidation.cost_basis,
             0,
             liquidation.trigger_underlying_price,
             liquidation.trigger_hour,
             1
      from public.gacha_s2_market_liquidations liquidation

      union all

      select trade.trade_id::text,
             trade.user_id,
             trade.symbol,
             trade.position_type,
             trade.multiplier,
             trade.side,
             trade.quantity,
             trade.unit_price,
             trade.gross_points,
             trade.fee_points,
             trade.net_points,
             trade.removed_cost_basis,
             trade.unit_price,
             0,
             trade.traded_at,
             2
      from public.gacha_s2_market_trades trade
      where trade.multiplier >= 2
    ) timeline
    order by user_id, symbol, position_type, multiplier, event_at, event_order, event_id
  loop
    insert into market_floor_exact_state(user_id, symbol, position_type, multiplier)
    values (v_event.user_id, v_event.symbol, v_event.position_type, v_event.multiplier)
    on conflict do nothing;

    select * into v_state
    from market_floor_exact_state
    where user_id = v_event.user_id
      and symbol = v_event.symbol
      and position_type = v_event.position_type
      and multiplier = v_event.multiplier
    for update;

    if v_event.event_type = 'tick' then
      v_liquidated := false;
      v_adverse := v_state.previous_underlying_price is not null and (
        (v_event.position_type = 'long'
          and v_event.underlying_price < v_state.previous_underlying_price)
        or
        (v_event.position_type = 'inverse'
          and v_event.underlying_price > v_state.previous_underlying_price)
      );

      if v_state.total_quantity > 0 then
        v_threshold := case
          when v_event.position_type = 'inverse' then ceil(
            v_state.entry_underlying_price * (1 + 1.0 / v_event.multiplier)
          )::integer
          else floor(
            v_state.entry_underlying_price * (1 - 1.0 / v_event.multiplier)
          )::integer
        end;
        v_liquidated := (
          v_event.position_type = 'long' and v_event.underlying_price <= v_threshold
        ) or (
          v_event.position_type = 'inverse' and v_event.underlying_price >= v_threshold
        );
      end if;

      if v_liquidated then
        select -coalesce(sum(remaining_cost), 0)
        into v_qualified_profit
        from market_floor_exact_lots
        where user_id = v_event.user_id
          and symbol = v_event.symbol
          and position_type = v_event.position_type
          and multiplier = v_event.multiplier
          and qualified
          and remaining_quantity > 0;

        update market_floor_exact_state
        set total_quantity = 0,
            total_cost = 0,
            entry_underlying_price = 0,
            previous_underlying_price = v_event.underlying_price,
            realized_floor_profit = realized_floor_profit + v_qualified_profit
        where user_id = v_event.user_id
          and symbol = v_event.symbol
          and position_type = v_event.position_type
          and multiplier = v_event.multiplier;

        update market_floor_exact_lots
        set remaining_quantity = 0, remaining_cost = 0
        where user_id = v_event.user_id
          and symbol = v_event.symbol
          and position_type = v_event.position_type
          and multiplier = v_event.multiplier;

      else
        if v_state.total_quantity > 0
           and v_event.product_price = 100
           and v_adverse
        then
          update market_floor_exact_lots
          set qualified = true
          where user_id = v_event.user_id
            and symbol = v_event.symbol
            and position_type = v_event.position_type
            and multiplier = v_event.multiplier
            and remaining_quantity > 0
            and not qualified;
        end if;

        update market_floor_exact_state
        set previous_underlying_price = v_event.underlying_price
        where user_id = v_event.user_id
          and symbol = v_event.symbol
          and position_type = v_event.position_type
          and multiplier = v_event.multiplier;
      end if;

    elsif v_event.event_type = 'liquidation' then
      if v_state.total_quantity > 0 then
        select -coalesce(sum(remaining_cost), 0)
        into v_qualified_profit
        from market_floor_exact_lots
        where user_id = v_event.user_id
          and symbol = v_event.symbol
          and position_type = v_event.position_type
          and multiplier = v_event.multiplier
          and qualified
          and remaining_quantity > 0;

        update market_floor_exact_state
        set total_quantity = 0,
            total_cost = 0,
            entry_underlying_price = 0,
            realized_floor_profit = realized_floor_profit + v_qualified_profit
        where user_id = v_event.user_id
          and symbol = v_event.symbol
          and position_type = v_event.position_type
          and multiplier = v_event.multiplier;

        update market_floor_exact_lots
        set remaining_quantity = 0, remaining_cost = 0
        where user_id = v_event.user_id
          and symbol = v_event.symbol
          and position_type = v_event.position_type
          and multiplier = v_event.multiplier;
      end if;

    elsif v_event.event_type = 'buy' then
      v_buy_cost := v_event.gross_points + v_event.fee_points;
      select underlying.price into v_buy_underlying
      from public.gacha_s2_market_prices underlying
      where underlying.symbol = v_event.symbol
        and underlying.hour_at <= v_event.event_at
      order by underlying.hour_at desc
      limit 1;

      if v_buy_underlying is null then
        raise exception 'MARKET_FLOOR_CORRECTION_UNDERLYING_MISSING';
      end if;

      update market_floor_exact_state
      set entry_underlying_price = case
            when total_cost <= 0 then v_buy_underlying
            else round((
              entry_underlying_price::numeric * total_cost
              + v_buy_underlying::numeric * v_buy_cost
            ) / (total_cost + v_buy_cost))::integer
          end,
          total_quantity = total_quantity + v_event.quantity,
          total_cost = total_cost + v_buy_cost
      where user_id = v_event.user_id
        and symbol = v_event.symbol
        and position_type = v_event.position_type
        and multiplier = v_event.multiplier;

      if v_event.unit_price = 100 then
        insert into market_floor_exact_lots(
          user_id, symbol, position_type, multiplier,
          remaining_quantity, remaining_cost
        ) values (
          v_event.user_id, v_event.symbol, v_event.position_type, v_event.multiplier,
          v_event.quantity, v_buy_cost
        );
      end if;

    else
      if v_state.total_quantity <= 0 or v_event.quantity > v_state.total_quantity then
        raise exception 'MARKET_FLOOR_CORRECTION_LEDGER_MISMATCH';
      end if;

      v_ratio := v_event.quantity::numeric / v_state.total_quantity;
      select coalesce(sum(
        case when qualified then
          v_event.net_points::numeric * (remaining_quantity * v_ratio) / v_event.quantity
          - remaining_cost * v_ratio
        else 0 end
      ), 0)
      into v_qualified_profit
      from market_floor_exact_lots
      where user_id = v_event.user_id
        and symbol = v_event.symbol
        and position_type = v_event.position_type
        and multiplier = v_event.multiplier
        and remaining_quantity > 0;

      update market_floor_exact_lots
      set remaining_quantity = greatest(0, remaining_quantity * (1 - v_ratio)),
          remaining_cost = greatest(0, remaining_cost * (1 - v_ratio))
      where user_id = v_event.user_id
        and symbol = v_event.symbol
        and position_type = v_event.position_type
        and multiplier = v_event.multiplier
        and remaining_quantity > 0;

      update market_floor_exact_state
      set total_quantity = greatest(0, total_quantity - v_event.quantity),
          total_cost = greatest(0, total_cost - v_event.removed_cost_basis),
          entry_underlying_price = case
            when total_quantity - v_event.quantity <= 0 then 0
            else entry_underlying_price
          end,
          realized_floor_profit = realized_floor_profit + v_qualified_profit
      where user_id = v_event.user_id
        and symbol = v_event.symbol
        and position_type = v_event.position_type
        and multiplier = v_event.multiplier;
    end if;
  end loop;
end
$calculate$;

create temporary table market_floor_exact_recovery on commit drop as
with latest_mark as (
  select distinct on (price.symbol, price.position_type, price.multiplier)
         price.symbol, price.position_type, price.multiplier, price.price
  from public.gacha_s2_market_product_prices price
  where price.multiplier >= 2
  order by price.symbol, price.position_type, price.multiplier, price.hour_at desc
), realized as (
  select user_id, sum(realized_floor_profit) as profit
  from market_floor_exact_state
  group by user_id
), unrealized as (
  select lot.user_id,
         sum(lot.remaining_quantity * mark.price - lot.remaining_cost) as profit
  from market_floor_exact_lots lot
  join latest_mark mark
    on mark.symbol = lot.symbol
   and mark.position_type = lot.position_type
   and mark.multiplier = lot.multiplier
  where lot.qualified and lot.remaining_quantity > 0
  group by lot.user_id
)
select users.user_id,
       floor(greatest(0, coalesce(realized.profit, 0) + coalesce(unrealized.profit, 0)))::bigint
         as revised_recovery_amount
from (
  select user_id from realized
  union
  select user_id from unrealized
) users
left join realized using (user_id)
left join unrealized using (user_id)
where floor(greatest(0, coalesce(realized.profit, 0) + coalesce(unrealized.profit, 0)))::bigint > 0;

insert into public.gacha_s2_market_floor_recovery_corrections (
  operation_key,
  user_id,
  original_recovery_amount,
  recovered_before_correction,
  revised_recovery_amount,
  refund_points,
  effective_recovered_points,
  outstanding_points,
  points_before,
  points_after
)
select 'market-100p-floor-recovery-correction-20260813',
       users.user_id,
       coalesce(original.recovery_amount, 0),
       coalesce(original.recovered_points, 0),
       coalesce(exact.revised_recovery_amount, 0),
       greatest(0, coalesce(original.recovered_points, 0) - coalesce(exact.revised_recovery_amount, 0)),
       least(coalesce(original.recovered_points, 0), coalesce(exact.revised_recovery_amount, 0)),
       greatest(0, coalesce(exact.revised_recovery_amount, 0) - coalesce(original.recovered_points, 0)),
       state.points,
       state.points + greatest(
         0,
         coalesce(original.recovered_points, 0) - coalesce(exact.revised_recovery_amount, 0)
       )::integer
from (
  select user_id
  from public.gacha_s2_market_floor_recoveries
  where operation_key = 'market-100p-floor-recovery-20260813'
  union
  select user_id from market_floor_exact_recovery
) users
join public.gacha_s2_player_states state on state.user_id = users.user_id
left join public.gacha_s2_market_floor_recoveries original
  on original.operation_key = 'market-100p-floor-recovery-20260813'
 and original.user_id = users.user_id
left join market_floor_exact_recovery exact on exact.user_id = users.user_id
on conflict (operation_key, user_id) do nothing;

do $apply$
declare
  v_correction record;
begin
  for v_correction in
    select *
    from public.gacha_s2_market_floor_recovery_corrections
    where operation_key = 'market-100p-floor-recovery-correction-20260813'
      and applied_at is null
    order by user_id
    for update
  loop
    if v_correction.refund_points > 0 then
      update public.gacha_s2_player_states
      set points = points + v_correction.refund_points::integer,
          revision = revision + 1,
          updated_at = now()
      where user_id = v_correction.user_id;
    end if;

    update public.gacha_s2_market_floor_recovery_corrections
    set applied_at = now(),
        last_recovered_at = case
          when effective_recovered_points > 0 then now()
          else null
        end,
        updated_at = now()
    where operation_key = v_correction.operation_key
      and user_id = v_correction.user_id;
  end loop;
end
$apply$;

create or replace function public.gacha_s2_apply_market_floor_outstanding()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_outstanding bigint;
  v_withhold integer;
begin
  if new.points <= old.points then
    return new;
  end if;

  select outstanding_points into v_outstanding
  from public.gacha_s2_market_floor_recovery_corrections
  where operation_key = 'market-100p-floor-recovery-correction-20260813'
    and user_id = new.user_id
    and outstanding_points > 0
  for update;

  if not found then
    return new;
  end if;

  v_withhold := least((new.points - old.points)::bigint, v_outstanding)::integer;
  new.points := new.points - v_withhold;

  update public.gacha_s2_market_floor_recovery_corrections
  set effective_recovered_points = effective_recovered_points + v_withhold,
      outstanding_points = outstanding_points - v_withhold,
      last_recovered_at = now(),
      updated_at = now()
  where operation_key = 'market-100p-floor-recovery-correction-20260813'
    and user_id = new.user_id;

  return new;
end;
$$;

create trigger gacha_s2_apply_market_floor_outstanding_trigger
before update of points on public.gacha_s2_player_states
for each row
when (new.points > old.points)
execute function public.gacha_s2_apply_market_floor_outstanding();

revoke all on function public.gacha_s2_apply_market_floor_outstanding()
  from public, anon, authenticated;

insert into public.gacha_s2_mailbox (
  user_id, event_key, category, title, body, points
)
select account.id,
       'market-100p-floor-recovery-correction-notice-20260813',
       'SYSTEM',
       '[정정 안내] 캄스증권 파생상품 회수 기준',
       case
         when correction.user_id is not null and correction.refund_points > 0 then
           '파생상품 오류 수익 회수 기준을 정밀 재검증했습니다. '
           || '100P 매수 후 본주가 포지션 반대 방향으로 움직였지만 청산선에는 도달하지 않았고, '
           || '파생가격이 100P로 유지되어 손실 없이 버틴 이력이 있는 매수분만 대상으로 정정했습니다. '
           || '과회수된 ' || correction.refund_points || 'P를 즉시 반환했습니다. '
           || '정정된 회수 대상액은 ' || correction.revised_recovery_amount || 'P이며, '
           || '잔여 상계액은 ' || correction.outstanding_points || 'P입니다.'
         when correction.user_id is not null then
           '파생상품 오류 수익 회수 기준을 정밀 재검증했습니다. '
           || '100P 매수 후 본주가 포지션 반대 방향으로 움직였지만 청산선에는 도달하지 않았고, '
           || '파생가격이 100P로 유지되어 손실 없이 버틴 이력이 있는 매수분만 대상으로 정정했습니다. '
           || '정정된 회수 대상액은 ' || correction.revised_recovery_amount || 'P이며, '
           || '잔여 상계액은 ' || correction.outstanding_points || 'P입니다.'
         else
           '파생상품 오류 수익 회수 기준을 정밀 재검증하고 과회수분 반환을 완료했습니다. '
           || '대상 계정의 아이디와 닉네임은 공개하지 않습니다.'
       end,
       0
from public.gacha_s2_accounts account
left join public.gacha_s2_market_floor_recovery_corrections correction
  on correction.operation_key = 'market-100p-floor-recovery-correction-20260813'
 and correction.user_id = account.id
on conflict (user_id, event_key) do nothing;

do $verify$
declare
  v_source text;
begin
  if exists (
    select 1
    from public.gacha_s2_market_floor_recovery_corrections
    where operation_key = 'market-100p-floor-recovery-correction-20260813'
      and (
        applied_at is null
        or refund_points <> greatest(0, recovered_before_correction - revised_recovery_amount)
        or effective_recovered_points + outstanding_points <> revised_recovery_amount
      )
  ) then
    raise exception 'MARKET_FLOOR_RECOVERY_CORRECTION_BALANCE_FAILED';
  end if;

  if exists (select 1 from public.gacha_s2_player_states where points < 0) then
    raise exception 'MARKET_FLOOR_RECOVERY_CORRECTION_NEGATIVE_POINTS';
  end if;

  v_source := pg_get_functiondef(
    'public.gacha_s2_apply_market_floor_outstanding()'::regprocedure
  );
  if v_source not like '%gacha_s2_market_floor_recovery_corrections%'
     or v_source not like '%effective_recovered_points = effective_recovered_points + v_withhold%'
  then
    raise exception 'MARKET_FLOOR_RECOVERY_CORRECTION_TRIGGER_GUARD_FAILED';
  end if;
end
$verify$;
