-- Recover abnormal profit created by derivative purchases at the former 100P floor.
-- The calculation follows the live pooled-average holding model. It attributes mixed lots
-- proportionally, nets realized losses/liquidations, and marks remaining floor lots to market.

create table if not exists public.gacha_s2_market_floor_recoveries (
  operation_key text not null check (length(operation_key) between 1 and 160),
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  realized_floor_profit bigint not null,
  unrealized_floor_profit bigint not null,
  recovery_amount bigint not null check (recovery_amount > 0),
  recovered_points bigint not null default 0 check (recovered_points >= 0),
  outstanding_points bigint not null check (outstanding_points >= 0),
  points_before integer not null check (points_before >= 0),
  points_after integer not null check (points_after >= 0),
  applied_at timestamptz,
  last_recovered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (operation_key, user_id),
  constraint gacha_s2_market_floor_recoveries_balance_check
    check (recovered_points + outstanding_points = recovery_amount)
);

create index if not exists gacha_s2_market_floor_recoveries_outstanding_idx
  on public.gacha_s2_market_floor_recoveries(user_id)
  where outstanding_points > 0;

alter table public.gacha_s2_market_floor_recoveries enable row level security;
revoke all on table public.gacha_s2_market_floor_recoveries from public, anon, authenticated;
grant select on table public.gacha_s2_market_floor_recoveries to service_role;

lock table public.gacha_s2_player_states in share row exclusive mode;
lock table public.gacha_s2_market_holdings in share row exclusive mode;
lock table public.gacha_s2_market_trades in share row exclusive mode;
lock table public.gacha_s2_market_liquidations in share row exclusive mode;
lock table public.gacha_s2_market_product_prices in share row exclusive mode;
lock table public.gacha_s2_market_prices in share row exclusive mode;

create temporary table market_floor_calc_state (
  user_id uuid not null,
  symbol text not null,
  position_type text not null,
  multiplier smallint not null,
  total_quantity numeric not null default 0,
  floor_quantity numeric not null default 0,
  floor_cost numeric not null default 0,
  realized_floor_profit numeric not null default 0,
  primary key (user_id, symbol, position_type, multiplier)
) on commit drop;

do $calculate$
declare
  v_event record;
  v_state market_floor_calc_state%rowtype;
  v_ratio numeric;
  v_floor_quantity_sold numeric;
  v_floor_cost_sold numeric;
  v_floor_proceeds numeric;
begin
  for v_event in
    select ledger.*
    from (
      select trade.trade_id::text as event_id,
             trade.user_id,
             trade.symbol,
             trade.position_type,
             trade.multiplier,
             trade.side as event_type,
             trade.quantity,
             trade.unit_price,
             trade.gross_points,
             trade.fee_points,
             trade.net_points,
             trade.traded_at as event_at,
             0 as event_order
      from public.gacha_s2_market_trades trade
      where trade.multiplier >= 2

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
             liquidation.liquidated_at,
             1
      from public.gacha_s2_market_liquidations liquidation
    ) ledger
    order by user_id, symbol, position_type, multiplier, event_at, event_order, event_id
  loop
    insert into market_floor_calc_state(user_id, symbol, position_type, multiplier)
    values (v_event.user_id, v_event.symbol, v_event.position_type, v_event.multiplier)
    on conflict do nothing;

    select * into v_state
    from market_floor_calc_state
    where user_id = v_event.user_id
      and symbol = v_event.symbol
      and position_type = v_event.position_type
      and multiplier = v_event.multiplier
    for update;

    if v_event.event_type = 'buy' then
      update market_floor_calc_state
      set total_quantity = total_quantity + v_event.quantity,
          floor_quantity = floor_quantity + case when v_event.unit_price = 100 then v_event.quantity else 0 end,
          floor_cost = floor_cost + case
            when v_event.unit_price = 100 then v_event.gross_points + v_event.fee_points
            else 0
          end
      where user_id = v_event.user_id
        and symbol = v_event.symbol
        and position_type = v_event.position_type
        and multiplier = v_event.multiplier;

    elsif v_event.event_type = 'sell' then
      if v_state.total_quantity <= 0 or v_event.quantity > v_state.total_quantity then
        raise exception 'MARKET_FLOOR_RECOVERY_LEDGER_MISMATCH';
      end if;

      v_ratio := v_event.quantity::numeric / v_state.total_quantity;
      v_floor_quantity_sold := v_state.floor_quantity * v_ratio;
      v_floor_cost_sold := v_state.floor_cost * v_ratio;
      v_floor_proceeds := case
        when v_event.quantity > 0
          then v_event.net_points::numeric * v_floor_quantity_sold / v_event.quantity
        else 0
      end;

      update market_floor_calc_state
      set total_quantity = greatest(0, total_quantity - v_event.quantity),
          floor_quantity = greatest(0, floor_quantity - v_floor_quantity_sold),
          floor_cost = greatest(0, floor_cost - v_floor_cost_sold),
          realized_floor_profit = realized_floor_profit + v_floor_proceeds - v_floor_cost_sold
      where user_id = v_event.user_id
        and symbol = v_event.symbol
        and position_type = v_event.position_type
        and multiplier = v_event.multiplier;

    else
      update market_floor_calc_state
      set total_quantity = 0,
          floor_quantity = 0,
          floor_cost = 0,
          realized_floor_profit = realized_floor_profit - floor_cost
      where user_id = v_event.user_id
        and symbol = v_event.symbol
        and position_type = v_event.position_type
        and multiplier = v_event.multiplier;
    end if;
  end loop;
end
$calculate$;

create temporary table market_floor_user_recovery on commit drop as
with product_mark as (
  select distinct on (price.symbol, price.position_type, price.multiplier)
         price.symbol, price.position_type, price.multiplier, price.price
  from public.gacha_s2_market_product_prices price
  order by price.symbol, price.position_type, price.multiplier, price.hour_at desc
), attributed as (
  select calc.user_id,
         calc.realized_floor_profit,
         case
           when holding.user_id is null or calc.floor_quantity <= 0 then 0::numeric
           when exists (
             select 1
             from public.gacha_s2_market_prices underlying
             where underlying.symbol = holding.symbol
               and underlying.hour_at > holding.liquidation_checked_at
               and (
                 (holding.position_type = 'long' and underlying.price <= floor(
                   holding.entry_underlying_price * (1 - 1.0 / holding.multiplier)
                 ))
                 or
                 (holding.position_type = 'inverse' and underlying.price >= ceil(
                   holding.entry_underlying_price * (1 + 1.0 / holding.multiplier)
                 ))
               )
           ) then -calc.floor_cost
           else calc.floor_quantity * product_mark.price - calc.floor_cost
         end as unrealized_floor_profit
  from market_floor_calc_state calc
  left join public.gacha_s2_market_holdings holding
    on holding.user_id = calc.user_id
   and holding.symbol = calc.symbol
   and holding.position_type = calc.position_type
   and holding.multiplier = calc.multiplier
  left join product_mark
    on product_mark.symbol = calc.symbol
   and product_mark.position_type = calc.position_type
   and product_mark.multiplier = calc.multiplier
)
select user_id,
       floor(sum(realized_floor_profit))::bigint as realized_floor_profit,
       floor(sum(unrealized_floor_profit))::bigint as unrealized_floor_profit,
       floor(greatest(0, sum(realized_floor_profit + unrealized_floor_profit)))::bigint as recovery_amount
from attributed
group by user_id
having floor(greatest(0, sum(realized_floor_profit + unrealized_floor_profit)))::bigint > 0;

do $validate$
declare
  v_target_count integer;
  v_total_recovery bigint;
begin
  select count(*)::integer, coalesce(sum(recovery_amount), 0)::bigint
  into v_target_count, v_total_recovery
  from market_floor_user_recovery;

  if v_target_count <= 0 or v_total_recovery <= 0 then
    raise exception 'MARKET_FLOOR_RECOVERY_EMPTY';
  end if;
end
$validate$;

insert into public.gacha_s2_market_floor_recoveries (
  operation_key,
  user_id,
  realized_floor_profit,
  unrealized_floor_profit,
  recovery_amount,
  recovered_points,
  outstanding_points,
  points_before,
  points_after
)
select 'market-100p-floor-recovery-20260813',
       recovery.user_id,
       recovery.realized_floor_profit,
       recovery.unrealized_floor_profit,
       recovery.recovery_amount,
       0,
       recovery.recovery_amount,
       state.points,
       state.points
from market_floor_user_recovery recovery
join public.gacha_s2_player_states state on state.user_id = recovery.user_id
on conflict (operation_key, user_id) do nothing;

do $apply$
declare
  v_recovery record;
  v_points integer;
  v_deduct integer;
begin
  for v_recovery in
    select *
    from public.gacha_s2_market_floor_recoveries
    where operation_key = 'market-100p-floor-recovery-20260813'
      and applied_at is null
    order by user_id
    for update
  loop
    select points into v_points
    from public.gacha_s2_player_states
    where user_id = v_recovery.user_id
    for update;

    v_deduct := least(v_points::bigint, v_recovery.recovery_amount)::integer;

    update public.gacha_s2_player_states
    set points = points - v_deduct,
        revision = revision + case when v_deduct > 0 then 1 else 0 end,
        updated_at = case when v_deduct > 0 then now() else updated_at end
    where user_id = v_recovery.user_id;

    update public.gacha_s2_market_floor_recoveries
    set recovered_points = v_deduct,
        outstanding_points = recovery_amount - v_deduct,
        points_before = v_points,
        points_after = v_points - v_deduct,
        applied_at = now(),
        last_recovered_at = case when v_deduct > 0 then now() else null end,
        updated_at = now()
    where operation_key = v_recovery.operation_key
      and user_id = v_recovery.user_id;
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
  from public.gacha_s2_market_floor_recoveries
  where operation_key = 'market-100p-floor-recovery-20260813'
    and user_id = new.user_id
    and outstanding_points > 0
  for update;

  if not found then
    return new;
  end if;

  v_withhold := least((new.points - old.points)::bigint, v_outstanding)::integer;
  new.points := new.points - v_withhold;

  update public.gacha_s2_market_floor_recoveries
  set recovered_points = recovered_points + v_withhold,
      outstanding_points = outstanding_points - v_withhold,
      last_recovered_at = now(),
      updated_at = now()
  where operation_key = 'market-100p-floor-recovery-20260813'
    and user_id = new.user_id;

  return new;
end;
$$;

drop trigger if exists gacha_s2_apply_market_floor_outstanding_trigger
  on public.gacha_s2_player_states;
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
       'market-100p-floor-recovery-notice-20260813',
       'SYSTEM',
       '[안내] 캄스증권 파생상품 오류 조치 완료',
       case
         when recovery.user_id is not null then
           '캄스증권 파생상품 가격 하한 오류 조치를 완료했습니다. '
           || '100P 매수분에서 발생한 비정상 실현·미실현 순이익 '
           || recovery.recovery_amount || 'P를 회수 대상으로 확정했습니다. '
           || '현재 ' || recovery.recovered_points || 'P가 회수되었으며, '
           || case when recovery.outstanding_points > 0
             then '잔여 ' || recovery.outstanding_points || 'P는 향후 포인트 증가 시 자동 상계됩니다. '
             else '잔여 회수액은 없습니다. '
           end
           || '정상 가격 매수분과 원금은 회수 대상에서 제외했습니다.'
         else
           '캄스증권 파생상품 가격 하한 오류 수정과 비정상 수익 회수 조치를 완료했습니다. '
           || '100P 매수분에서 발생한 실현·미실현 순이익만 계산했으며, 정상 가격 매수분과 원금은 제외했습니다. '
           || '대상 계정의 아이디와 닉네임은 공개하지 않습니다.'
       end,
       0
from public.gacha_s2_accounts account
left join public.gacha_s2_market_floor_recoveries recovery
  on recovery.operation_key = 'market-100p-floor-recovery-20260813'
 and recovery.user_id = account.id
on conflict (user_id, event_key) do nothing;

do $verify$
declare
  v_source text;
begin
  if exists (
    select 1
    from public.gacha_s2_market_floor_recoveries
    where operation_key = 'market-100p-floor-recovery-20260813'
      and (
        applied_at is null
        or recovered_points < 0
        or outstanding_points < 0
        or recovered_points + outstanding_points <> recovery_amount
      )
  ) then
    raise exception 'MARKET_FLOOR_RECOVERY_BALANCE_FAILED';
  end if;

  if exists (select 1 from public.gacha_s2_player_states where points < 0) then
    raise exception 'MARKET_FLOOR_RECOVERY_NEGATIVE_POINTS';
  end if;

  v_source := pg_get_functiondef(
    'public.gacha_s2_apply_market_floor_outstanding()'::regprocedure
  );
  if v_source not like '%new.points <= old.points%'
     or v_source not like '%outstanding_points = outstanding_points - v_withhold%'
  then
    raise exception 'MARKET_FLOOR_OUTSTANDING_TRIGGER_GUARD_FAILED';
  end if;
end
$verify$;
