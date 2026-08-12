-- 캄스증권 파생상품: 일반, 레버리지 x2~x5, 인버스 x2~x5.
-- 실제 P 원금 한도는 전체/기초 종목별 각 1,000,000P다.
-- 레버리지 상품은 기초 종목의 시간봉 수익률을 매시간 배수 적용한다.
-- 진입가 대비 반대 방향으로 1/배수만큼 움직이면 전량 강제청산하며 추가 채무는 없다.

alter table public.gacha_s2_market_holdings
  add column if not exists position_type text not null default 'long',
  add column if not exists multiplier smallint not null default 1,
  add column if not exists entry_underlying_price integer,
  add column if not exists liquidation_checked_at timestamptz not null default now();

update public.gacha_s2_market_holdings holding
set entry_underlying_price = coalesce((
  select price.price
  from public.gacha_s2_market_prices price
  where price.symbol = holding.symbol
  order by price.hour_at desc
  limit 1
), (
  select asset.base_price
  from public.gacha_s2_market_assets asset
  where asset.symbol = holding.symbol
))
where entry_underlying_price is null;

alter table public.gacha_s2_market_holdings
  alter column entry_underlying_price set not null;

alter table public.gacha_s2_market_holdings
  drop constraint if exists gacha_s2_market_holdings_pkey;
alter table public.gacha_s2_market_holdings
  add constraint gacha_s2_market_holdings_pkey
  primary key (user_id, symbol, position_type, multiplier);
alter table public.gacha_s2_market_holdings
  drop constraint if exists gacha_s2_market_holdings_product_check;
alter table public.gacha_s2_market_holdings
  add constraint gacha_s2_market_holdings_product_check check (
    (position_type = 'long' and multiplier between 1 and 5)
    or (position_type = 'inverse' and multiplier between 2 and 5)
  );
alter table public.gacha_s2_market_holdings
  drop constraint if exists gacha_s2_market_holdings_entry_underlying_price_check;
alter table public.gacha_s2_market_holdings
  add constraint gacha_s2_market_holdings_entry_underlying_price_check
  check (entry_underlying_price >= 100);

alter table public.gacha_s2_market_trades
  add column if not exists position_type text not null default 'long',
  add column if not exists multiplier smallint not null default 1;
alter table public.gacha_s2_market_trades
  drop constraint if exists gacha_s2_market_trades_product_check;
alter table public.gacha_s2_market_trades
  add constraint gacha_s2_market_trades_product_check check (
    (position_type = 'long' and multiplier between 1 and 5)
    or (position_type = 'inverse' and multiplier between 2 and 5)
  );

create table if not exists public.gacha_s2_market_product_prices (
  symbol text not null references public.gacha_s2_market_assets(symbol) on delete cascade,
  position_type text not null,
  multiplier smallint not null,
  hour_at timestamptz not null,
  price integer not null check (price >= 100),
  change_bps integer not null check (change_bps between -15000 and 15000),
  created_at timestamptz not null default now(),
  primary key (symbol, position_type, multiplier, hour_at),
  constraint gacha_s2_market_product_prices_product_check check (
    (position_type = 'long' and multiplier between 1 and 5)
    or (position_type = 'inverse' and multiplier between 2 and 5)
  )
);

create index if not exists gacha_s2_market_product_prices_history_idx
  on public.gacha_s2_market_product_prices(symbol, position_type, multiplier, hour_at desc);

alter table public.gacha_s2_market_product_prices enable row level security;
revoke all on table public.gacha_s2_market_product_prices from public, anon, authenticated;

create table if not exists public.gacha_s2_market_liquidations (
  liquidation_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  symbol text not null references public.gacha_s2_market_assets(symbol),
  position_type text not null,
  multiplier smallint not null,
  quantity integer not null check (quantity > 0),
  cost_basis bigint not null check (cost_basis > 0),
  entry_underlying_price integer not null check (entry_underlying_price >= 100),
  trigger_underlying_price integer not null check (trigger_underlying_price >= 100),
  trigger_hour timestamptz not null,
  loss_points bigint not null check (loss_points < 0),
  liquidated_at timestamptz not null default now(),
  constraint gacha_s2_market_liquidations_product_check check (
    (position_type = 'long' and multiplier between 2 and 5)
    or (position_type = 'inverse' and multiplier between 2 and 5)
  ),
  unique (user_id, symbol, position_type, multiplier, trigger_hour)
);

create index if not exists gacha_s2_market_liquidations_user_idx
  on public.gacha_s2_market_liquidations(user_id, liquidated_at desc);

alter table public.gacha_s2_market_liquidations enable row level security;
revoke all on table public.gacha_s2_market_liquidations from public, anon, authenticated;

create or replace function public.gacha_s2_market_ensure_product_prices(p_now timestamptz default now())
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hour timestamptz;
  v_cursor timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext('gacha_s2_market_product_prices'));
  v_hour := public.gacha_s2_market_ensure_prices(p_now);

  if not exists (select 1 from public.gacha_s2_market_product_prices) then
    insert into public.gacha_s2_market_product_prices(
      symbol, position_type, multiplier, hour_at, price, change_bps
    )
    select base.symbol, product.position_type, product.multiplier,
           v_hour, base.price,
           greatest(-15000, least(
             15000,
             base.change_bps * product.multiplier
               * case when product.position_type = 'inverse' then -1 else 1 end
           ))
    from public.gacha_s2_market_prices base
    cross join (values
      ('long'::text, 1::smallint),
      ('long'::text, 2::smallint),
      ('long'::text, 3::smallint),
      ('long'::text, 4::smallint),
      ('long'::text, 5::smallint),
      ('inverse'::text, 2::smallint),
      ('inverse'::text, 3::smallint),
      ('inverse'::text, 4::smallint),
      ('inverse'::text, 5::smallint)
    ) product(position_type, multiplier)
    where base.hour_at = v_hour
    on conflict do nothing;
    return v_hour;
  end if;

  select max(hour_at) + interval '1 hour'
  into v_cursor
  from public.gacha_s2_market_product_prices;

  while v_cursor <= v_hour loop
    insert into public.gacha_s2_market_product_prices(
      symbol, position_type, multiplier, hour_at, price, change_bps
    )
    select calculated.symbol,
           calculated.position_type,
           calculated.multiplier,
           v_cursor,
           calculated.next_price,
           greatest(-15000, least(
             15000,
             round((calculated.next_price::numeric / calculated.previous_product_price - 1) * 10000)::integer
           ))
    from (
      select asset.symbol,
             product.position_type,
             product.multiplier,
             previous_product.price as previous_product_price,
             greatest(100, least(
               asset.base_price * 10,
               round(previous_product.price * (
                 1 + ((current_underlying.price::numeric / previous_underlying.price) - 1)
                   * product.multiplier
                   * case when product.position_type = 'inverse' then -1 else 1 end
               ))::integer
             )) as next_price
      from public.gacha_s2_market_assets asset
      cross join (values
        ('long'::text, 1::smallint),
        ('long'::text, 2::smallint),
        ('long'::text, 3::smallint),
        ('long'::text, 4::smallint),
        ('long'::text, 5::smallint),
        ('inverse'::text, 2::smallint),
        ('inverse'::text, 3::smallint),
        ('inverse'::text, 4::smallint),
        ('inverse'::text, 5::smallint)
      ) product(position_type, multiplier)
      join public.gacha_s2_market_prices current_underlying
        on current_underlying.symbol = asset.symbol and current_underlying.hour_at = v_cursor
      join public.gacha_s2_market_prices previous_underlying
        on previous_underlying.symbol = asset.symbol and previous_underlying.hour_at = v_cursor - interval '1 hour'
      join public.gacha_s2_market_product_prices previous_product
        on previous_product.symbol = asset.symbol
       and previous_product.position_type = product.position_type
       and previous_product.multiplier = product.multiplier
       and previous_product.hour_at = v_cursor - interval '1 hour'
      where asset.active
    ) calculated
    on conflict do nothing;
    v_cursor := v_cursor + interval '1 hour';
  end loop;

  return v_hour;
end;
$$;

revoke all on function public.gacha_s2_market_ensure_product_prices(timestamptz) from public, anon, authenticated;
grant execute on function public.gacha_s2_market_ensure_product_prices(timestamptz) to service_role;

create or replace function public.gacha_s2_market_settle_liquidations(
  p_user_id uuid,
  p_hour timestamptz
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_holding public.gacha_s2_market_holdings%rowtype;
  v_trigger record;
  v_count integer := 0;
begin
  if p_user_id is null or p_hour is null then return 0; end if;
  perform pg_advisory_xact_lock(hashtext('gacha_s2_market_user:' || p_user_id::text));

  for v_holding in
    select *
    from public.gacha_s2_market_holdings
    where user_id = p_user_id and multiplier >= 2
    for update
  loop
    select price.hour_at, price.price
    into v_trigger
    from public.gacha_s2_market_prices price
    where price.symbol = v_holding.symbol
      and price.hour_at > v_holding.liquidation_checked_at
      and price.hour_at <= p_hour
      and (
        (v_holding.position_type = 'long'
          and price.price <= floor(v_holding.entry_underlying_price * (1 - 1.0 / v_holding.multiplier)))
        or
        (v_holding.position_type = 'inverse'
          and price.price >= ceil(v_holding.entry_underlying_price * (1 + 1.0 / v_holding.multiplier)))
      )
    order by price.hour_at
    limit 1;

    if found then
      delete from public.gacha_s2_market_holdings
      where user_id = v_holding.user_id
        and symbol = v_holding.symbol
        and position_type = v_holding.position_type
        and multiplier = v_holding.multiplier;

      insert into public.gacha_s2_market_liquidations(
        user_id, symbol, position_type, multiplier, quantity, cost_basis,
        entry_underlying_price, trigger_underlying_price, trigger_hour, loss_points
      ) values (
        v_holding.user_id, v_holding.symbol, v_holding.position_type, v_holding.multiplier,
        v_holding.quantity, v_holding.cost_basis, v_holding.entry_underlying_price,
        v_trigger.price, v_trigger.hour_at, -v_holding.cost_basis
      ) on conflict do nothing;
      v_count := v_count + 1;
    else
      update public.gacha_s2_market_holdings
      set liquidation_checked_at = p_hour
      where user_id = v_holding.user_id
        and symbol = v_holding.symbol
        and position_type = v_holding.position_type
        and multiplier = v_holding.multiplier;
    end if;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.gacha_s2_market_settle_liquidations(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.gacha_s2_market_settle_liquidations(uuid, timestamptz) to service_role;

create or replace function public.gacha_s2_get_market_state(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hour timestamptz;
  v_day_start timestamptz;
  v_revision bigint;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', '로그인이 필요합니다.');
  end if;

  select revision into v_revision
  from public.gacha_s2_player_states
  where user_id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', '계정 상태를 찾을 수 없습니다.');
  end if;

  v_hour := public.gacha_s2_market_ensure_product_prices(now());
  perform public.gacha_s2_market_settle_liquidations(p_user_id, v_hour);
  v_day_start := date_trunc('day', v_hour at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';

  return jsonb_build_object(
    'hourAt', floor(extract(epoch from v_hour) * 1000)::bigint,
    'historyStartsAt', floor(extract(epoch from v_day_start) * 1000)::bigint,
    'nextUpdateAt', floor(extract(epoch from (v_hour + interval '1 hour')) * 1000)::bigint,
    'playerRevision', v_revision,
    'feeRate', 0.015,
    'totalInvestmentCap', 1000000,
    'perAssetInvestmentCap', 1000000,
    'investedPoints', coalesce((
      select sum(cost_basis) from public.gacha_s2_market_holdings where user_id = p_user_id
    ), 0),
    'marketValue', coalesce((
      select sum(holding.quantity::bigint * product_price.price)
      from public.gacha_s2_market_holdings holding
      join public.gacha_s2_market_product_prices product_price
        on product_price.symbol = holding.symbol
       and product_price.position_type = holding.position_type
       and product_price.multiplier = holding.multiplier
       and product_price.hour_at = v_hour
      where holding.user_id = p_user_id
    ), 0),
    'realizedPnl', coalesce((
      select sum(realized_pnl) from public.gacha_s2_market_trades where user_id = p_user_id
    ), 0) + coalesce((
      select sum(loss_points) from public.gacha_s2_market_liquidations where user_id = p_user_id
    ), 0),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'symbol', asset.symbol,
        'name', asset.display_name,
        'cardId', asset.card_id,
        'price', underlying.price,
        'changeBps', underlying.change_bps,
        'regime', underlying.regime,
        'investedPoints', coalesce(asset_holding.cost_basis, 0),
        'quantity', coalesce(spot_holding.quantity, 0),
        'costBasis', coalesce(spot_holding.cost_basis, 0),
        'averagePrice', case when coalesce(spot_holding.quantity, 0) > 0
          then round(spot_holding.cost_basis::numeric / spot_holding.quantity)::bigint else 0 end,
        'marketValue', coalesce(spot_holding.quantity::bigint * spot_price.price, 0),
        'unrealizedPnl', coalesce(spot_holding.quantity::bigint * spot_price.price - spot_holding.cost_basis, 0),
        'history', coalesce(spot_history.rows, '[]'::jsonb),
        'positions', coalesce(positions.rows, '[]'::jsonb)
      ) order by asset.sort_order)
      from public.gacha_s2_market_assets asset
      join public.gacha_s2_market_prices underlying
        on underlying.symbol = asset.symbol and underlying.hour_at = v_hour
      join public.gacha_s2_market_product_prices spot_price
        on spot_price.symbol = asset.symbol
       and spot_price.position_type = 'long' and spot_price.multiplier = 1
       and spot_price.hour_at = v_hour
      left join public.gacha_s2_market_holdings spot_holding
        on spot_holding.user_id = p_user_id and spot_holding.symbol = asset.symbol
       and spot_holding.position_type = 'long' and spot_holding.multiplier = 1
      left join lateral (
        select sum(cost_basis) as cost_basis
        from public.gacha_s2_market_holdings
        where user_id = p_user_id and symbol = asset.symbol
      ) asset_holding on true
      left join lateral (
        select jsonb_agg(jsonb_build_object(
          'at', floor(extract(epoch from sample.hour_at) * 1000)::bigint,
          'price', sample.price
        ) order by sample.hour_at) as rows
        from (
          select hour_at, price
          from public.gacha_s2_market_product_prices
          where symbol = asset.symbol and position_type = 'long' and multiplier = 1
            and hour_at >= v_day_start and hour_at <= v_hour
          order by hour_at desc
          limit 24
        ) sample
      ) spot_history on true
      left join lateral (
        select jsonb_agg(jsonb_build_object(
          'positionType', product.position_type,
          'multiplier', product.multiplier,
          'label', case
            when product.position_type = 'inverse' then '인버스 x' || product.multiplier
            when product.multiplier = 1 then '일반'
            else '레버리지 x' || product.multiplier end,
          'price', product_price.price,
          'changeBps', product_price.change_bps,
          'quantity', coalesce(holding.quantity, 0),
          'costBasis', coalesce(holding.cost_basis, 0),
          'averagePrice', case when coalesce(holding.quantity, 0) > 0
            then round(holding.cost_basis::numeric / holding.quantity)::bigint else 0 end,
          'marketValue', coalesce(holding.quantity::bigint * product_price.price, 0),
          'unrealizedPnl', coalesce(holding.quantity::bigint * product_price.price - holding.cost_basis, 0),
          'entryUnderlyingPrice', coalesce(holding.entry_underlying_price, 0),
          'liquidationPrice', case
            when holding.quantity is null or product.multiplier = 1 then 0
            when product.position_type = 'inverse'
              then ceil(holding.entry_underlying_price * (1 + 1.0 / product.multiplier))::integer
            else floor(holding.entry_underlying_price * (1 - 1.0 / product.multiplier))::integer
          end,
          'history', coalesce(product_history.rows, '[]'::jsonb)
        ) order by product.sort_order) as rows
        from (values
          ('long'::text, 1::smallint, 1),
          ('long'::text, 2::smallint, 2),
          ('long'::text, 3::smallint, 3),
          ('long'::text, 4::smallint, 4),
          ('long'::text, 5::smallint, 5),
          ('inverse'::text, 2::smallint, 6),
          ('inverse'::text, 3::smallint, 7),
          ('inverse'::text, 4::smallint, 8),
          ('inverse'::text, 5::smallint, 9)
        ) product(position_type, multiplier, sort_order)
        join public.gacha_s2_market_product_prices product_price
          on product_price.symbol = asset.symbol
         and product_price.position_type = product.position_type
         and product_price.multiplier = product.multiplier
         and product_price.hour_at = v_hour
        left join public.gacha_s2_market_holdings holding
          on holding.user_id = p_user_id and holding.symbol = asset.symbol
         and holding.position_type = product.position_type and holding.multiplier = product.multiplier
        left join lateral (
          select jsonb_agg(jsonb_build_object(
            'at', floor(extract(epoch from sample.hour_at) * 1000)::bigint,
            'price', sample.price
          ) order by sample.hour_at) as rows
          from (
            select hour_at, price
            from public.gacha_s2_market_product_prices
            where symbol = asset.symbol
              and position_type = product.position_type and multiplier = product.multiplier
              and hour_at >= v_day_start and hour_at <= v_hour
            order by hour_at desc
            limit 24
          ) sample
        ) product_history on true
      ) positions on true
      where asset.active
    ), '[]'::jsonb),
    'recentTrades', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tradeId', recent.entry_id,
        'symbol', recent.symbol,
        'name', asset.display_name,
        'side', recent.side,
        'positionType', recent.position_type,
        'multiplier', recent.multiplier,
        'productLabel', case
          when recent.position_type = 'inverse' then '인버스 x' || recent.multiplier
          when recent.multiplier = 1 then '일반'
          else '레버리지 x' || recent.multiplier end,
        'quantity', recent.quantity,
        'unitPrice', recent.unit_price,
        'feePoints', recent.fee_points,
        'netPoints', recent.net_points,
        'realizedPnl', recent.realized_pnl,
        'tradedAt', floor(extract(epoch from recent.traded_at) * 1000)::bigint
      ) order by recent.traded_at desc)
      from (
        select * from (
          select trade.trade_id::text as entry_id, trade.symbol, trade.side,
                 trade.position_type, trade.multiplier, trade.quantity, trade.unit_price,
                 trade.fee_points, trade.net_points, trade.realized_pnl, trade.traded_at
          from public.gacha_s2_market_trades trade
          where trade.user_id = p_user_id
          union all
          select liquidation.liquidation_id::text, liquidation.symbol, 'liquidation',
                 liquidation.position_type, liquidation.multiplier, liquidation.quantity, 0,
                 0, 0, liquidation.loss_points, liquidation.liquidated_at
          from public.gacha_s2_market_liquidations liquidation
          where liquidation.user_id = p_user_id
        ) ledger
        order by traded_at desc
        limit 20
      ) recent
      join public.gacha_s2_market_assets asset on asset.symbol = recent.symbol
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.gacha_s2_market_trade(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_symbol text,
  p_side text,
  p_quantity integer,
  p_position_type text,
  p_multiplier integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hour timestamptz;
  v_revision bigint;
  v_points integer;
  v_price integer;
  v_underlying_price integer;
  v_gross bigint;
  v_fee bigint;
  v_cost bigint;
  v_total_basis bigint;
  v_asset_basis bigint;
  v_holding public.gacha_s2_market_holdings%rowtype;
  v_removed_basis bigint := 0;
  v_proceeds bigint := 0;
  v_realized bigint := 0;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_symbol is null or p_symbol !~ '^[A-Z]{2,8}$'
    or p_side not in ('buy', 'sell')
    or p_quantity is null or p_quantity < 1 or p_quantity > 100000
    or not (
      (p_position_type = 'long' and p_multiplier between 1 and 5)
      or (p_position_type = 'inverse' and p_multiplier between 2 and 5)
    ) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '매매 주문 형식이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  select revision, points into v_revision, v_points
  from public.gacha_s2_player_states
  where user_id = p_user_id
  for update;
  if not found then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'marketTrade',
    'expectedRevision', p_expected_revision,
    'symbol', p_symbol,
    'side', p_side,
    'quantity', p_quantity,
    'positionType', p_position_type,
    'multiplier', p_multiplier
  )::text, 'sha256'), 'hex');

  select * into v_previous
  from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'marketTrade' then
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

  if not exists (
    select 1 from public.gacha_s2_market_assets where symbol = p_symbol and active
  ) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '거래할 수 없는 종목입니다.', v_revision, null, null
    );
  end if;

  v_hour := public.gacha_s2_market_ensure_product_prices(now());
  perform public.gacha_s2_market_settle_liquidations(p_user_id, v_hour);

  select product_price.price into v_price
  from public.gacha_s2_market_product_prices product_price
  where product_price.symbol = p_symbol
    and product_price.position_type = p_position_type
    and product_price.multiplier = p_multiplier
    and product_price.hour_at = v_hour;
  select price into v_underlying_price
  from public.gacha_s2_market_prices
  where symbol = p_symbol and hour_at = v_hour;
  if v_price is null or v_underlying_price is null then raise exception 'MARKET_PRODUCT_PRICE_MISSING'; end if;

  v_gross := v_price::bigint * p_quantity;
  v_fee := greatest(1, ceil(v_gross * 0.015)::bigint);

  if p_side = 'buy' then
    v_cost := v_gross + v_fee;
    if v_cost > 2147483647 or v_points < v_cost then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'COMMAND_REJECTED', '매수에 필요한 포인트가 부족합니다.',
        v_revision, null, jsonb_build_object('requiredPoints', v_cost)
      );
    end if;

    select coalesce(sum(cost_basis), 0) into v_total_basis
    from public.gacha_s2_market_holdings where user_id = p_user_id;
    select coalesce(sum(cost_basis), 0) into v_asset_basis
    from public.gacha_s2_market_holdings where user_id = p_user_id and symbol = p_symbol;

    if v_total_basis + v_cost > 1000000 then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'COMMAND_REJECTED', '전체 투자 한도는 1,000,000P입니다.',
        v_revision, null, jsonb_build_object('investmentCap', 1000000, 'investedPoints', v_total_basis)
      );
    end if;
    if v_asset_basis + v_cost > 1000000 then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'COMMAND_REJECTED', '종목당 투자 한도는 1,000,000P입니다.',
        v_revision, null, jsonb_build_object('assetInvestmentCap', 1000000, 'assetInvestedPoints', v_asset_basis)
      );
    end if;

    insert into public.gacha_s2_market_holdings(
      user_id, symbol, position_type, multiplier, quantity, cost_basis,
      entry_underlying_price, liquidation_checked_at
    ) values (
      p_user_id, p_symbol, p_position_type, p_multiplier, p_quantity, v_cost,
      v_underlying_price, v_hour
    )
    on conflict (user_id, symbol, position_type, multiplier) do update
    set entry_underlying_price = round((
          public.gacha_s2_market_holdings.entry_underlying_price::numeric
            * public.gacha_s2_market_holdings.cost_basis
          + excluded.entry_underlying_price::numeric * excluded.cost_basis
        ) / (public.gacha_s2_market_holdings.cost_basis + excluded.cost_basis))::integer,
        quantity = public.gacha_s2_market_holdings.quantity + excluded.quantity,
        cost_basis = public.gacha_s2_market_holdings.cost_basis + excluded.cost_basis,
        liquidation_checked_at = v_hour,
        updated_at = now();

    update public.gacha_s2_player_states
    set points = points - v_cost, revision = revision + 1, updated_at = now()
    where user_id = p_user_id returning revision into v_revision;
  else
    select * into v_holding
    from public.gacha_s2_market_holdings
    where user_id = p_user_id and symbol = p_symbol
      and position_type = p_position_type and multiplier = p_multiplier
    for update;
    if not found or v_holding.quantity < p_quantity then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'COMMAND_REJECTED', '선택 상품의 매도 가능 수량이 부족합니다.',
        v_revision, null, jsonb_build_object('ownedQuantity', coalesce(v_holding.quantity, 0))
      );
    end if;

    v_removed_basis := case when p_quantity = v_holding.quantity
      then v_holding.cost_basis
      else round(v_holding.cost_basis::numeric * p_quantity / v_holding.quantity)::bigint end;
    v_proceeds := greatest(0, v_gross - v_fee);
    v_realized := v_proceeds - v_removed_basis;

    if v_proceeds > 2147483647 - v_points then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'COMMAND_REJECTED', '포인트 보유 상한을 초과해 매도할 수 없습니다.',
        v_revision, null, jsonb_build_object('proceeds', v_proceeds)
      );
    end if;

    if p_quantity = v_holding.quantity then
      delete from public.gacha_s2_market_holdings
      where user_id = p_user_id and symbol = p_symbol
        and position_type = p_position_type and multiplier = p_multiplier;
    else
      update public.gacha_s2_market_holdings
      set quantity = quantity - p_quantity,
          cost_basis = cost_basis - v_removed_basis,
          updated_at = now()
      where user_id = p_user_id and symbol = p_symbol
        and position_type = p_position_type and multiplier = p_multiplier;
    end if;

    update public.gacha_s2_player_states
    set points = points + v_proceeds, revision = revision + 1, updated_at = now()
    where user_id = p_user_id returning revision into v_revision;
  end if;

  insert into public.gacha_s2_market_trades(
    user_id, symbol, position_type, multiplier, side, quantity, unit_price,
    gross_points, fee_points, net_points, removed_cost_basis, realized_pnl, idempotency_key
  ) values (
    p_user_id, p_symbol, p_position_type, p_multiplier, p_side, p_quantity, v_price,
    v_gross, v_fee, case when p_side = 'buy' then -(v_gross + v_fee) else v_proceeds end,
    v_removed_basis, v_realized, p_idempotency_key
  );

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
      'symbol', p_symbol,
      'positionType', p_position_type,
      'multiplier', p_multiplier,
      'side', p_side,
      'quantity', p_quantity,
      'unitPrice', v_price,
      'grossPoints', v_gross,
      'feePoints', v_fee,
      'netPoints', case when p_side = 'buy' then -(v_gross + v_fee) else v_proceeds end,
      'realizedPnl', v_realized
    )
  );

  insert into public.gacha_s2_idempotency(
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id, p_idempotency_key, 'marketTrade', v_request_hash, v_response, now() + interval '24 hours'
  );
  insert into public.gacha_s2_command_audit(
    user_id, command_id, command_type, request_hash, expected_revision, committed_revision
  ) values (
    p_user_id, p_idempotency_key, 'marketTrade', v_request_hash, p_expected_revision, v_revision
  );

  return v_response;
end;
$$;

-- 구버전 클라이언트는 추가 인자가 없다. 일반 x1 주문으로 안전하게 연결한다.
create or replace function public.gacha_s2_market_trade(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_symbol text,
  p_side text,
  p_quantity integer
)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.gacha_s2_market_trade(
    p_user_id, p_expected_revision, p_idempotency_key,
    p_symbol, p_side, p_quantity, 'long', 1
  );
$$;

revoke all on function public.gacha_s2_get_market_state(uuid) from public, anon, authenticated;
grant execute on function public.gacha_s2_get_market_state(uuid) to service_role;
revoke all on function public.gacha_s2_market_trade(uuid, bigint, text, text, text, integer, text, integer) from public, anon, authenticated;
grant execute on function public.gacha_s2_market_trade(uuid, bigint, text, text, text, integer, text, integer) to service_role;
revoke all on function public.gacha_s2_market_trade(uuid, bigint, text, text, text, integer) from public, anon, authenticated;
grant execute on function public.gacha_s2_market_trade(uuid, bigint, text, text, text, integer) to service_role;

do $$
declare
  v_trade_src text;
  v_state_src text;
begin
  v_trade_src := pg_get_functiondef(
    'public.gacha_s2_market_trade(uuid,bigint,text,text,text,integer,text,integer)'::regprocedure
  );
  v_state_src := pg_get_functiondef('public.gacha_s2_get_market_state(uuid)'::regprocedure);
  if v_trade_src not like '%1,000,000P%'
     or v_trade_src not like '%p_position_type%'
     or v_trade_src not like '%gacha_s2_market_settle_liquidations%'
     or v_state_src not like '%positions%'
     or v_state_src not like '%market_liquidations%' then
    raise exception 'MARKET_DERIVATIVES_GUARD_FAILED';
  end if;
end;
$$;
