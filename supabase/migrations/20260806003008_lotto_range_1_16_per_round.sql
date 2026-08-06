-- 로또 번호 범위 1~18 -> 1~16.
--
-- 범위를 회차에 기록한다. 적용 시점에 열려 있던 회차(20260806-1000)는 이미 500장 넘게
-- 1~18 기준으로 팔렸고 그중 288장이 17·18 을 포함했다. 전역으로 바꾸면 그 표들만 맞출 수
-- 없는 번호를 들고 추첨되므로, 기존 회차는 18 로 고정하고 새로 만들어지는 회차부터 16 을 쓴다.
alter table public.gacha_s2_lotto_rounds
  add column if not exists max_number integer not null default 16;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.gacha_s2_lotto_rounds'::regclass
      and conname = 'gacha_s2_lotto_rounds_max_number_check'
  ) then
    alter table public.gacha_s2_lotto_rounds
      add constraint gacha_s2_lotto_rounds_max_number_check
      check (max_number between 6 and 18);
  end if;
end;
$$;

-- 이미 존재하는 회차(추첨 완료분 + 그때 열려 있던 회차)는 전부 1~18 규칙으로 팔렸다.
update public.gacha_s2_lotto_rounds set max_number = 18;

-- 추첨 함수는 본문이 길고 이번 변경은 뽑기 범위 한 줄뿐이다.
-- 전체를 다시 쓰면 옮겨 적다 틀릴 위험이 있으므로 현재 정의를 가져와 그 부분만 바꿔 다시 만든다.
do $$
declare v_src text;
begin
  v_src := pg_get_functiondef('public.gacha_s2_lotto_settle_due(timestamptz)'::regprocedure);
  if position('generate_series(1, 18)' in v_src) = 0 then
    raise exception 'expected draw range literal not found in settle function';
  end if;
  v_src := replace(v_src, 'generate_series(1, 18)', 'generate_series(1, v_round.max_number)');
  execute v_src;
end;
$$;

-- 구매 검증: 해당 회차의 범위를 넘는 번호를 거부한다.
-- 테이블 CHECK 의 gacha_s2_lotto_numbers_valid 는 1~18 그대로 둔다. 기존 표를 계속
-- 유효하게 두어야 하고, 실제 회차별 규칙은 아래에서 강제하기 때문이다.
create or replace function public.gacha_s2_buy_lotto_ticket(p_user_id uuid, p_expected_revision bigint, p_idempotency_key text, p_numbers integer[])
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_now timestamptz := now();
  v_draw_at timestamptz;
  v_round_id text;
  v_max_number integer;
  v_revision bigint;
  v_points integer;
  v_ticket_count integer;
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
      p_idempotency_key, 'VALIDATION_FAILED', '로또 번호는 서로 다른 6개를 선택해야 합니다.',
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

  -- 회차별 번호 범위 검사. 회차가 만들어진 뒤라야 알 수 있어 여기서 한다.
  select max_number into v_max_number
  from public.gacha_s2_lotto_rounds where round_id = v_round_id;
  if v_max_number is null then
    raise exception 'LOTTO_ROUND_MISSING';
  end if;
  if (select max(value) from unnest(v_numbers) as picked(value)) > v_max_number then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED',
      format('로또 번호 1~%s 중 서로 다른 6개를 선택해야 합니다.', v_max_number),
      greatest(coalesce(p_expected_revision, 0), 0), null,
      jsonb_build_object('field', 'numbers', 'maxNumber', v_max_number)
    );
  end if;

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

  select count(*)::integer into v_ticket_count
  from public.gacha_s2_lotto_tickets
  where round_id = v_round_id and user_id = p_user_id;
  if v_ticket_count >= 2 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이번 회차 로또 2장을 모두 구매했습니다.',
      v_revision, null, jsonb_build_object('roundId', v_round_id, 'ticketLimit', 2)
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
      'costPoints', 1000,
      'ticketCount', v_ticket_count + 1,
      'ticketLimit', 2,
      'maxNumber', v_max_number
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
$function$;

revoke all on function public.gacha_s2_buy_lotto_ticket(uuid, bigint, text, integer[]) from public, anon, authenticated;
grant execute on function public.gacha_s2_buy_lotto_ticket(uuid, bigint, text, integer[]) to service_role;

do $$
declare
  v_src text;
  v_open_max integer;
  v_default text;
begin
  v_src := pg_get_functiondef('public.gacha_s2_lotto_settle_due(timestamptz)'::regprocedure);
  if v_src not like '%generate_series(1, v_round.max_number)%' then
    raise exception 'settle still draws from a fixed range';
  end if;

  -- 적용 시점에 열린 회차는 1~18 로 팔렸으니 18 을 유지해야 한다.
  select max_number into v_open_max
  from public.gacha_s2_lotto_rounds where status = 'open' order by draw_at limit 1;
  if v_open_max is not null and v_open_max <> 18 then
    raise exception 'open round max_number is %, tickets were sold under 1-18', v_open_max;
  end if;

  -- 다음 회차부터 16 이 되려면 컬럼 기본값이 16 이어야 한다.
  select column_default into v_default from information_schema.columns
  where table_name = 'gacha_s2_lotto_rounds' and column_name = 'max_number';
  if v_default not like '16%' then
    raise exception 'new rounds would not use 1-16: default is %', v_default;
  end if;
end;
$$;
