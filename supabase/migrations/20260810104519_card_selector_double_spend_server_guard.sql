-- 카드 선택권 이중 소모를 서버에서 막는다.
--
-- 클라이언트는 이미 고쳤지만 그것만으로는 부족하다. 화면 코드는 새로고침해야 바뀌는데
-- 이미 열어 둔 탭은 옛 코드로 계속 돌아, 수정 배포 뒤에도 같은 손실이 이어졌다
-- (배포 후 20분간 21건 추가 발생). 옛 탭에서도 즉시 막으려면 서버가 거절해야 한다.
--
-- 같은 카드를 15초 안에 다시 고르는 것은 사람이 카드를 다시 골라 확인까지 누른 결과로
-- 보기 어렵다. 실제 이중 소모 사례의 간격은 평균 4.8초였다. 다른 카드를 고르는 것은
-- 막지 않는다. "각각 선택"은 정상 사용이다.
create table if not exists public.gacha_s2_card_selector_recent (
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  card_id text not null,
  redeemed_at timestamptz not null default now(),
  primary key (user_id, card_id)
);

alter table public.gacha_s2_card_selector_recent enable row level security;
revoke all on table public.gacha_s2_card_selector_recent from public, anon, authenticated;

do $$
declare v_src text;
begin
  v_src := pg_get_functiondef('public.gacha_s2_redeem_card_selector(uuid,bigint,text,text,text)'::regprocedure);

  -- 선택권 보유 확인 바로 뒤에 중복 가드를 끼운다.
  v_src := replace(
    v_src,
    '  perform 1' || E'\n' || '  from public.gacha_s2_card_catalog',
    '  if exists ('
    || E'\n    select 1 from public.gacha_s2_card_selector_recent'
    || E'\n    where user_id = p_user_id and card_id = p_card_id'
    || E'\n      and redeemed_at > now() - interval ''15 seconds'''
    || E'\n  ) then'
    || E'\n    return public.gacha_s2_command_error('
    || E'\n      p_idempotency_key,'
    || E'\n      ''COMMAND_REJECTED'','
    || E'\n      ''방금 같은 카드를 받았습니다. 다른 카드를 고르거나 잠시 후 다시 시도해 주세요.'','
    || E'\n      v_revision,'
    || E'\n      public.gacha_s2_get_player_snapshot(p_user_id),'
    || E'\n      null'
    || E'\n    );'
    || E'\n  end if;'
    || E'\n\n  perform 1'
    || E'\n  from public.gacha_s2_card_catalog'
  );

  -- 지급 직후 기록을 남긴다.
  v_src := replace(
    v_src,
    '  insert into public.gacha_s2_collection_records (user_id, card_id)',
    '  insert into public.gacha_s2_card_selector_recent (user_id, card_id, redeemed_at)'
    || E'\n  values (p_user_id, p_card_id, now())'
    || E'\n  on conflict (user_id, card_id) do update set redeemed_at = now();'
    || E'\n\n  insert into public.gacha_s2_collection_records (user_id, card_id)'
  );

  if v_src not like '%gacha_s2_card_selector_recent%' then
    raise exception 'guard not applied';
  end if;
  if v_src not like '%15 seconds%' then
    raise exception 'guard window not applied';
  end if;
  execute v_src;
end;
$$;

do $$
declare v_src text;
begin
  v_src := pg_get_functiondef('public.gacha_s2_redeem_card_selector(uuid,bigint,text,text,text)'::regprocedure);
  -- 기존 검증이 그대로 살아 있어야 한다.
  if v_src not like '%보유하지 않은 카드 선택권입니다%' then
    raise exception 'ownership check lost';
  end if;
  if v_src not like '%등급 카드만 선택할 수 있습니다%' then
    raise exception 'rarity check lost';
  end if;
  if v_src not like '%IDEMPOTENCY_KEY_REUSED%' then
    raise exception 'idempotency check lost';
  end if;
  -- 가드가 지급보다 앞서야 한다. 뒤에 있으면 이미 준 뒤라 의미가 없다.
  if position('card_selector_recent' in v_src) > position('insert into public.gacha_s2_player_cards' in v_src) then
    raise exception 'guard must run before the card is granted';
  end if;
end;
$$;
