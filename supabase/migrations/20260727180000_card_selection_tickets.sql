-- Event-only SS/SSS card selection tickets.
-- Tickets are intentionally excluded from support-pack probability tables.

begin;

update public.gacha_s2_balance_versions
set config = jsonb_set(
  jsonb_set(
    config,
    '{supportItems,ssCardSelector}',
    '{"name":"SS 카드 선택권","category":"선택권","effect":"원하는 SS 카드 1장 선택","cardSelectorRarity":"SS"}'::jsonb,
    true
  ),
  '{supportItems,sssCardSelector}',
  '{"name":"SSS 카드 선택권","category":"선택권","effect":"원하는 SSS 카드 1장 선택","cardSelectorRarity":"SSS"}'::jsonb,
  true
)
where active;

update public.gacha_s2_player_states
set support_items = jsonb_set(
  jsonb_set(
    support_items,
    '{ssCardSelector}',
    to_jsonb(coalesce((support_items->>'ssCardSelector')::integer, 0)),
    true
  ),
  '{sssCardSelector}',
  to_jsonb(coalesce((support_items->>'sssCardSelector')::integer, 0)),
  true
);

alter table public.gacha_s2_player_states
  alter column support_items set default '{
    "energySmall":0,"energyMedium":0,"energyLarge":0,
    "enhance5":0,"enhance10":0,"destructionGuard":0,
    "cardExpPotion":0,"cardExpPotionLarge":0,"exp30m":0,"exp2h":0,
    "generalTicket":0,"eliteTicket":0,"raceTicket":0,"premiumTicket":0,
    "ssCardSelector":0,"sssCardSelector":0,
    "adventureRunReset":0,"quickBattleReset":0
  }'::jsonb;

create or replace function public.gacha_s2_redeem_card_selector(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_item_id text,
  p_card_id text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_items jsonb;
  v_target_rarity text;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_snapshot jsonb;
  v_response jsonb;
begin
  v_target_rarity := case p_item_id
    when 'ssCardSelector' then 'SS'
    when 'sssCardSelector' then 'SSS'
    else null
  end;

  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null
    or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or v_target_rarity is null
    or p_card_id is null or length(trim(p_card_id)) < 1 or length(p_card_id) > 80 then
    return public.gacha_s2_command_error(
      p_idempotency_key,
      'VALIDATION_FAILED',
      '카드 선택권 사용 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0),
      null,
      null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'redeemCardSelector',
    'expectedRevision', p_expected_revision,
    'itemId', p_item_id,
    'cardId', p_card_id
  )::text, 'sha256'), 'hex');

  select revision, support_items
  into v_revision, v_items
  from public.gacha_s2_player_states
  where user_id = p_user_id
  for update;

  if not found then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'AUTH_REQUIRED', '계정 상태가 없습니다.', 0, null, null
    );
  end if;

  select *
  into v_previous
  from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;

  if found then
    if v_previous.request_hash <> v_request_hash
      or v_previous.command_type <> 'redeemCardSelector' then
      return public.gacha_s2_command_error(
        p_idempotency_key,
        'IDEMPOTENCY_KEY_REUSED',
        '동일 요청 키를 재사용할 수 없습니다.',
        v_revision,
        null,
        null
      );
    end if;
    return v_previous.response;
  end if;

  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(
      p_idempotency_key,
      'VERSION_CONFLICT',
      '최신 상태를 다시 불러와야 합니다.',
      v_revision,
      public.gacha_s2_get_player_snapshot(p_user_id),
      null
    );
  end if;

  if coalesce((v_items->>p_item_id)::integer, 0) < 1 then
    return public.gacha_s2_command_error(
      p_idempotency_key,
      'COMMAND_REJECTED',
      '보유하지 않은 카드 선택권입니다.',
      v_revision,
      null,
      null
    );
  end if;

  perform 1
  from public.gacha_s2_card_catalog
  where card_id = p_card_id
    and rarity = v_target_rarity
    and not is_group;

  if not found then
    return public.gacha_s2_command_error(
      p_idempotency_key,
      'COMMAND_REJECTED',
      format('%s 등급 카드만 선택할 수 있습니다.', v_target_rarity),
      v_revision,
      null,
      null
    );
  end if;

  insert into public.gacha_s2_player_cards (user_id, card_id, copies)
  values (p_user_id, p_card_id, 1)
  on conflict (user_id, card_id) do update
    set copies = public.gacha_s2_player_cards.copies + 1,
        updated_at = now();

  insert into public.gacha_s2_collection_records (user_id, card_id)
  values (p_user_id, p_card_id)
  on conflict (user_id, card_id) do nothing;

  update public.gacha_s2_player_states
  set support_items = jsonb_set(
        support_items,
        array[p_item_id],
        to_jsonb((support_items->>p_item_id)::integer - 1),
        false
      ),
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
    'serverSeed', null,
    'snapshot', v_snapshot,
    'result', jsonb_build_object(
      'itemId', p_item_id,
      'cardId', p_card_id,
      'rarity', v_target_rarity
    )
  );

  insert into public.gacha_s2_idempotency (
    user_id, idempotency_key, command_type, request_hash, response, expires_at
  ) values (
    p_user_id,
    p_idempotency_key,
    'redeemCardSelector',
    v_request_hash,
    v_response,
    now() + interval '24 hours'
  );

  insert into public.gacha_s2_command_audit (
    user_id, command_id, command_type, request_hash,
    expected_revision, committed_revision, server_seed
  ) values (
    p_user_id,
    p_idempotency_key,
    'redeemCardSelector',
    v_request_hash,
    p_expected_revision,
    v_revision,
    null
  );

  return v_response;
end;
$$;

revoke all on function public.gacha_s2_redeem_card_selector(uuid, bigint, text, text, text)
  from public, anon, authenticated;
grant execute on function public.gacha_s2_redeem_card_selector(uuid, bigint, text, text, text)
  to service_role;

do $$
declare
  v_config jsonb;
  v_missing integer;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active;

  if v_config->'supportItems'->'ssCardSelector'->>'cardSelectorRarity' <> 'SS'
    or v_config->'supportItems'->'sssCardSelector'->>'cardSelectorRarity' <> 'SSS' then
    raise exception 'card selection ticket config missing';
  end if;

  if v_config->'supportPack'->'items' ? 'ssCardSelector'
    or v_config->'supportPack'->'items' ? 'sssCardSelector' then
    raise exception 'event-only card selection tickets must not enter support-pack rates';
  end if;

  select count(*) into v_missing
  from public.gacha_s2_player_states
  where not support_items ? 'ssCardSelector'
    or not support_items ? 'sssCardSelector'
    or (support_items->>'ssCardSelector')::integer < 0
    or (support_items->>'sssCardSelector')::integer < 0;

  if v_missing <> 0 then
    raise exception 'card selection ticket inventory backfill failed: % rows', v_missing;
  end if;
end;
$$;

commit;
