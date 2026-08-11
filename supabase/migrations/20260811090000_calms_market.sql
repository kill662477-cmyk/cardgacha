-- 캄스증권: 공통 시간봉 시세와 실제 P 매매 원장.
-- 모든 가격 생성과 매매는 서버에서 직렬화한다. 기존 미니게임 일일 보상 한도와 연결하지 않는다.

create table if not exists public.gacha_s2_market_assets (
  symbol text primary key check (symbol ~ '^[A-Z]{2,8}$'),
  display_name text not null,
  card_id text not null,
  base_price integer not null check (base_price >= 100),
  sort_order integer not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.gacha_s2_market_prices (
  symbol text not null references public.gacha_s2_market_assets(symbol) on delete cascade,
  hour_at timestamptz not null,
  price integer not null check (price >= 100),
  change_bps integer not null check (change_bps between -3000 and 3000),
  regime text not null check (regime in ('open', 'normal', 'trend', 'shock')),
  trend_direction smallint not null default 0 check (trend_direction between -1 and 1),
  trend_remaining smallint not null default 0 check (trend_remaining between 0 and 8),
  created_at timestamptz not null default now(),
  primary key (symbol, hour_at)
);

create index if not exists gacha_s2_market_prices_history_idx
  on public.gacha_s2_market_prices(symbol, hour_at desc);

create table if not exists public.gacha_s2_market_holdings (
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  symbol text not null references public.gacha_s2_market_assets(symbol) on delete cascade,
  quantity integer not null check (quantity > 0),
  cost_basis bigint not null check (cost_basis > 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, symbol)
);

create table if not exists public.gacha_s2_market_trades (
  trade_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  symbol text not null references public.gacha_s2_market_assets(symbol),
  side text not null check (side in ('buy', 'sell')),
  quantity integer not null check (quantity > 0),
  unit_price integer not null check (unit_price >= 100),
  gross_points bigint not null check (gross_points > 0),
  fee_points bigint not null check (fee_points > 0),
  net_points bigint not null,
  removed_cost_basis bigint not null default 0 check (removed_cost_basis >= 0),
  realized_pnl bigint not null default 0,
  idempotency_key text not null,
  traded_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create index if not exists gacha_s2_market_trades_user_idx
  on public.gacha_s2_market_trades(user_id, traded_at desc);

alter table public.gacha_s2_market_assets enable row level security;
alter table public.gacha_s2_market_prices enable row level security;
alter table public.gacha_s2_market_holdings enable row level security;
alter table public.gacha_s2_market_trades enable row level security;
revoke all on table public.gacha_s2_market_assets from public, anon, authenticated;
revoke all on table public.gacha_s2_market_prices from public, anon, authenticated;
revoke all on table public.gacha_s2_market_holdings from public, anon, authenticated;
revoke all on table public.gacha_s2_market_trades from public, anon, authenticated;

insert into public.gacha_s2_market_assets(symbol, display_name, card_id, base_price, sort_order)
values
  ('KYH', '김윤환', 'kimyunhwan-4', 12000, 1),
  ('NDS', '남덕선', 'namdeokseon-12', 9400, 2),
  ('TMT', '토마토', 'tomato-11', 15000, 3),
  ('JDD', '지두두', 'jidudu-14', 13500, 4),
  ('SUN', '햇살', 'haetsal-12', 10800, 5),
  ('JJK', '찌킹', 'jjiking-12', 8800, 6),
  ('CHR', '치리', 'chiri-19', 7600, 7),
  ('SJY', '소주양', 'sojuyang-13', 11200, 8),
  ('JHR', '주하랑', 'juharang-18', 16500, 9),
  ('JOY', '임조이', 'imjoy-12', 9900, 10),
  ('VTM', '비타밍', 'vitaming-14', 12800, 11),
  ('MJG', '먼진', 'meonjin-12', 8200, 12),
  ('ARS', '아리송이', 'arisongi-11', 14200, 13),
  ('NGN', '낭니', 'nangni-8', 17000, 14)
on conflict (symbol) do update
set display_name = excluded.display_name,
    card_id = excluded.card_id,
    base_price = excluded.base_price,
    sort_order = excluded.sort_order,
    active = true;

create or replace function public.gacha_s2_market_random(p_seed text)
returns numeric
language sql
immutable
parallel safe
set search_path = public, pg_temp
as $$
  select ((hashtextextended(p_seed, 0) & 9223372036854775807)::numeric / 9223372036854775807::numeric);
$$;

create or replace function public.gacha_s2_market_ensure_prices(p_now timestamptz default now())
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hour timestamptz := date_trunc('hour', p_now);
  v_first_hour timestamptz;
  v_cursor timestamptz;
  v_asset public.gacha_s2_market_assets%rowtype;
  v_previous public.gacha_s2_market_prices%rowtype;
  v_average numeric;
  v_mode_roll numeric;
  v_magnitude_roll numeric;
  v_direction_roll numeric;
  v_rate numeric;
  v_direction smallint;
  v_remaining smallint;
  v_regime text;
  v_price integer;
  v_seed text;
begin
  perform pg_advisory_xact_lock(hashtext('gacha_s2_market:' || v_hour::text));

  if not exists (select 1 from public.gacha_s2_market_prices) then
    insert into public.gacha_s2_market_prices(
      symbol, hour_at, price, change_bps, regime, trend_direction, trend_remaining
    )
    select symbol, v_hour, base_price, 0, 'open', 0, 0
    from public.gacha_s2_market_assets
    where active
    on conflict do nothing;
    return v_hour;
  end if;

  select min(last_hour + interval '1 hour') into v_first_hour
  from (
    select a.symbol, coalesce(max(p.hour_at), v_hour - interval '1 hour') as last_hour
    from public.gacha_s2_market_assets a
    left join public.gacha_s2_market_prices p on p.symbol = a.symbol
    where a.active
    group by a.symbol
  ) pending;
  -- 장기간 비활성 뒤 첫 조회가 과거 전체 시간봉을 복원하느라 길어지지 않게 7일만 따라잡는다.
  v_cursor := greatest(v_hour - interval '168 hours', least(coalesce(v_first_hour, v_hour), v_hour));

  while v_cursor <= v_hour loop
    for v_asset in
      select * from public.gacha_s2_market_assets where active order by sort_order
    loop
      if exists (
        select 1 from public.gacha_s2_market_prices
        where symbol = v_asset.symbol and hour_at = v_cursor
      ) then
        continue;
      end if;

      select * into v_previous
      from public.gacha_s2_market_prices
      where symbol = v_asset.symbol and hour_at < v_cursor
      order by hour_at desc
      limit 1;

      if not found then
        insert into public.gacha_s2_market_prices(
          symbol, hour_at, price, change_bps, regime, trend_direction, trend_remaining
        ) values (v_asset.symbol, v_cursor, v_asset.base_price, 0, 'open', 0, 0)
        on conflict do nothing;
        continue;
      end if;

      select avg(price)::numeric into v_average
      from (
        select price
        from public.gacha_s2_market_prices
        where symbol = v_asset.symbol and hour_at < v_cursor
        order by hour_at desc
        limit 24
      ) history;

      v_seed := v_asset.symbol || ':' || to_char(v_cursor at time zone 'UTC', 'YYYYMMDDHH24');
      v_mode_roll := public.gacha_s2_market_random(v_seed || ':mode');
      v_magnitude_roll := public.gacha_s2_market_random(v_seed || ':magnitude');
      v_direction_roll := public.gacha_s2_market_random(v_seed || ':direction');
      v_direction := case when v_direction_roll < 0.5 then -1 else 1 end;

      if v_previous.trend_remaining > 0 then
        v_regime := 'trend';
        v_direction := v_previous.trend_direction;
        v_remaining := v_previous.trend_remaining - 1;
        v_rate := v_direction * (0.08 + v_magnitude_roll * 0.12);
      elsif v_mode_roll < 0.70 then
        v_regime := 'normal';
        v_remaining := 0;
        v_direction := 0;
        v_rate := (v_magnitude_roll * 0.24) - 0.12;
      elsif v_mode_roll < 0.95 then
        v_regime := 'trend';
        v_remaining := floor(2 + public.gacha_s2_market_random(v_seed || ':length') * 6)::smallint;
        v_rate := v_direction * (0.08 + v_magnitude_roll * 0.12);
      else
        v_regime := 'shock';
        v_remaining := 0;
        v_rate := v_direction * (0.20 + v_magnitude_roll * 0.10);
        v_direction := 0;
      end if;

      -- 24시간 평균에서 40% 이상 벗어났을 때만 약한 회귀 압력을 준다.
      if v_average is not null and v_previous.price > v_average * 1.40 then
        v_rate := v_rate - 0.03;
      elsif v_average is not null and v_previous.price < v_average * 0.60 then
        v_rate := v_rate + 0.03;
      end if;

      v_rate := greatest(-0.30, least(0.30, v_rate));
      v_price := greatest(
        100,
        least(v_asset.base_price * 10, round(v_previous.price * (1 + v_rate))::integer)
      );

      insert into public.gacha_s2_market_prices(
        symbol, hour_at, price, change_bps, regime, trend_direction, trend_remaining
      ) values (
        v_asset.symbol,
        v_cursor,
        v_price,
        round((v_price::numeric / v_previous.price - 1) * 10000)::integer,
        v_regime,
        v_direction,
        v_remaining
      )
      on conflict do nothing;
    end loop;
    v_cursor := v_cursor + interval '1 hour';
  end loop;

  return v_hour;
end;
$$;

create or replace function public.gacha_s2_get_market_state(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hour timestamptz;
  v_revision bigint;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', '로그인이 필요합니다.');
  end if;
  select revision into v_revision from public.gacha_s2_player_states where user_id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', '계정 상태를 찾을 수 없습니다.');
  end if;

  v_hour := public.gacha_s2_market_ensure_prices(now());

  return jsonb_build_object(
    'hourAt', floor(extract(epoch from v_hour) * 1000)::bigint,
    'nextUpdateAt', floor(extract(epoch from (v_hour + interval '1 hour')) * 1000)::bigint,
    'playerRevision', v_revision,
    'feeRate', 0.015,
    'totalInvestmentCap', 500000,
    'perAssetInvestmentCap', 500000,
    'investedPoints', coalesce((
      select sum(cost_basis) from public.gacha_s2_market_holdings where user_id = p_user_id
    ), 0),
    'marketValue', coalesce((
      select sum(h.quantity::bigint * p.price)
      from public.gacha_s2_market_holdings h
      join public.gacha_s2_market_prices p on p.symbol = h.symbol and p.hour_at = v_hour
      where h.user_id = p_user_id
    ), 0),
    'realizedPnl', coalesce((
      select sum(realized_pnl) from public.gacha_s2_market_trades where user_id = p_user_id
    ), 0),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'symbol', a.symbol,
        'name', a.display_name,
        'cardId', a.card_id,
        'price', p.price,
        'changeBps', p.change_bps,
        'regime', p.regime,
        'quantity', coalesce(h.quantity, 0),
        'costBasis', coalesce(h.cost_basis, 0),
        'averagePrice', case when coalesce(h.quantity, 0) > 0
          then round(h.cost_basis::numeric / h.quantity)::bigint else 0 end,
        'marketValue', coalesce(h.quantity::bigint * p.price, 0),
        'unrealizedPnl', coalesce(h.quantity::bigint * p.price - h.cost_basis, 0),
        'history', coalesce(history.rows, '[]'::jsonb)
      ) order by a.sort_order)
      from public.gacha_s2_market_assets a
      join public.gacha_s2_market_prices p on p.symbol = a.symbol and p.hour_at = v_hour
      left join public.gacha_s2_market_holdings h on h.user_id = p_user_id and h.symbol = a.symbol
      left join lateral (
        select jsonb_agg(jsonb_build_object(
          'at', floor(extract(epoch from samples.hour_at) * 1000)::bigint,
          'price', samples.price
        ) order by samples.hour_at) as rows
        from (
          select hour_at, price
          from public.gacha_s2_market_prices
          where symbol = a.symbol and hour_at <= v_hour
          order by hour_at desc
          limit 24
        ) samples
      ) history on true
      where a.active
    ), '[]'::jsonb),
    'recentTrades', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tradeId', t.trade_id,
        'symbol', t.symbol,
        'name', a.display_name,
        'side', t.side,
        'quantity', t.quantity,
        'unitPrice', t.unit_price,
        'feePoints', t.fee_points,
        'netPoints', t.net_points,
        'realizedPnl', t.realized_pnl,
        'tradedAt', floor(extract(epoch from t.traded_at) * 1000)::bigint
      ) order by t.traded_at desc)
      from (
        select * from public.gacha_s2_market_trades
        where user_id = p_user_id
        order by traded_at desc
        limit 20
      ) t
      join public.gacha_s2_market_assets a on a.symbol = t.symbol
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.gacha_s2_client_get_market_state()
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user_id uuid := public.gacha_s2_client_account_id();
  v_state jsonb;
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;
  v_state := public.gacha_s2_get_market_state(v_user_id);
  return jsonb_build_object('ok', true, 'serverTime', public.gacha_s2_now_ms(), 'state', v_state);
end;
$$;

create or replace function public.gacha_s2_market_trade(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_symbol text,
  p_side text,
  p_quantity integer
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
    or p_quantity is null or p_quantity < 1 or p_quantity > 100000 then
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
    'quantity', p_quantity
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

  v_hour := public.gacha_s2_market_ensure_prices(now());
  select price into v_price
  from public.gacha_s2_market_prices
  where symbol = p_symbol and hour_at = v_hour;
  if v_price is null then raise exception 'MARKET_PRICE_MISSING'; end if;

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
    select coalesce(cost_basis, 0) into v_asset_basis
    from public.gacha_s2_market_holdings where user_id = p_user_id and symbol = p_symbol;
    v_asset_basis := coalesce(v_asset_basis, 0);

    if v_total_basis + v_cost > 500000 then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'COMMAND_REJECTED', '전체 투자 한도는 500,000P입니다.',
        v_revision, null, jsonb_build_object('investmentCap', 500000, 'investedPoints', v_total_basis)
      );
    end if;
    if v_asset_basis + v_cost > 500000 then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'COMMAND_REJECTED', '종목당 투자 한도는 500,000P입니다.',
        v_revision, null, jsonb_build_object('assetInvestmentCap', 500000, 'assetInvestedPoints', v_asset_basis)
      );
    end if;

    insert into public.gacha_s2_market_holdings(user_id, symbol, quantity, cost_basis)
    values (p_user_id, p_symbol, p_quantity, v_cost)
    on conflict (user_id, symbol) do update
    set quantity = public.gacha_s2_market_holdings.quantity + excluded.quantity,
        cost_basis = public.gacha_s2_market_holdings.cost_basis + excluded.cost_basis,
        updated_at = now();

    update public.gacha_s2_player_states
    set points = points - v_cost, revision = revision + 1, updated_at = now()
    where user_id = p_user_id returning revision into v_revision;
  else
    select * into v_holding
    from public.gacha_s2_market_holdings
    where user_id = p_user_id and symbol = p_symbol
    for update;
    if not found or v_holding.quantity < p_quantity then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'COMMAND_REJECTED', '매도할 보유 수량이 부족합니다.',
        v_revision, null, jsonb_build_object('ownedQuantity', coalesce(v_holding.quantity, 0))
      );
    end if;

    v_removed_basis := case when p_quantity = v_holding.quantity
      then v_holding.cost_basis
      else round(v_holding.cost_basis::numeric * p_quantity / v_holding.quantity)::bigint end;
    v_proceeds := greatest(0, v_gross - v_fee);
    v_realized := v_proceeds - v_removed_basis;

    if p_quantity = v_holding.quantity then
      delete from public.gacha_s2_market_holdings
      where user_id = p_user_id and symbol = p_symbol;
    else
      update public.gacha_s2_market_holdings
      set quantity = quantity - p_quantity,
          cost_basis = cost_basis - v_removed_basis,
          updated_at = now()
      where user_id = p_user_id and symbol = p_symbol;
    end if;

    update public.gacha_s2_player_states
    set points = points + v_proceeds, revision = revision + 1, updated_at = now()
    where user_id = p_user_id returning revision into v_revision;
  end if;

  insert into public.gacha_s2_market_trades(
    user_id, symbol, side, quantity, unit_price, gross_points, fee_points,
    net_points, removed_cost_basis, realized_pnl, idempotency_key
  ) values (
    p_user_id, p_symbol, p_side, p_quantity, v_price, v_gross, v_fee,
    case when p_side = 'buy' then -(v_gross + v_fee) else v_proceeds end,
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

revoke all on function public.gacha_s2_market_random(text) from public, anon, authenticated;
revoke all on function public.gacha_s2_market_ensure_prices(timestamptz) from public, anon, authenticated;
revoke all on function public.gacha_s2_get_market_state(uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_client_get_market_state() from public, anon;
revoke all on function public.gacha_s2_market_trade(uuid, bigint, text, text, text, integer) from public, anon, authenticated;
grant execute on function public.gacha_s2_market_ensure_prices(timestamptz) to service_role;
grant execute on function public.gacha_s2_get_market_state(uuid) to service_role;
grant execute on function public.gacha_s2_client_get_market_state() to authenticated;
grant execute on function public.gacha_s2_market_trade(uuid, bigint, text, text, text, integer) to service_role;

do $$
begin
  if (select count(*) from public.gacha_s2_market_assets where active) <> 14 then
    raise exception 'CALMS_MARKET_ASSET_COUNT_INVALID';
  end if;
end;
$$;
