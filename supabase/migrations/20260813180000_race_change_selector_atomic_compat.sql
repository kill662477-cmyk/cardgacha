-- Cached-client-safe race selector.
-- The purchase and race change happen atomically; no new support_items key is stored.
begin;

do $balance$
declare
  v_config jsonb;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active
  for update;
  if v_config is null then raise exception 'active balance config missing'; end if;

  v_config := jsonb_set(v_config, '{directSupportItems}', coalesce(v_config->'directSupportItems', '{}'::jsonb), true);
  v_config := jsonb_set(
    v_config,
    '{directSupportItems,raceChangeSelector}',
    '{"name":"종족선택 변경권","price":20000000,"applyImmediately":true}'::jsonb,
    true
  );
  -- Never publish this ID in the legacy support-item catalog. Cached clients reject unknown IDs.
  v_config := v_config #- '{supportItems,raceChangeSelector}';

  update public.gacha_s2_balance_versions
  set config = v_config,
      config_hash = encode(digest(v_config::text, 'sha256'), 'hex')
  where active;
end;
$balance$;

-- Defensive cleanup. No account bought the selector during the disabled window, but preserve
-- any positive count by converting it into a one-time credit before removing the legacy key.
create table if not exists public.gacha_s2_race_selector_credits (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  credits integer not null default 0 check (credits >= 0),
  updated_at timestamptz not null default now()
);
alter table public.gacha_s2_race_selector_credits enable row level security;
revoke all on table public.gacha_s2_race_selector_credits from public, anon, authenticated;
grant select, insert, update on table public.gacha_s2_race_selector_credits to service_role;

insert into public.gacha_s2_race_selector_credits (user_id, credits, updated_at)
select user_id, greatest(0, coalesce((support_items->>'raceChangeSelector')::integer, 0)), now()
from public.gacha_s2_player_states
where coalesce((support_items->>'raceChangeSelector')::integer, 0) > 0
on conflict (user_id) do update
set credits = public.gacha_s2_race_selector_credits.credits + excluded.credits,
    updated_at = now();

update public.gacha_s2_player_states
set support_items = support_items - 'raceChangeSelector', updated_at = now()
where support_items ? 'raceChangeSelector';

do $snapshot_patch$
declare
  v_def text;
  v_next text;
  v_source text := '''archetype'', coalesce(c.archetype_override, (select catalog.archetype from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id))';
  v_race_fragment text := ', ''race'', coalesce(c.race_override, (select catalog.race from public.gacha_s2_card_catalog catalog where catalog.card_id = c.card_id))';
begin
  select pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure) into v_def;
  if strpos(v_def, v_race_fragment) = 0 then
    v_next := replace(v_def, v_source, v_source || v_race_fragment);
    if v_next = v_def or strpos(v_next, v_race_fragment) = 0 then
      raise exception 'player snapshot race patch source mismatch';
    end if;
    execute v_next;
  end if;
end;
$snapshot_patch$;

create or replace function public.gacha_s2_purchase_fixed_support_item(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text,
  p_item_id text,
  p_target_card_id text,
  p_race text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_points integer;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_config jsonb;
  v_product jsonb;
  v_price integer;
  v_previous_race text;
  v_credit integer := 0;
  v_snapshot jsonb;
  v_response jsonb;
begin
  if p_user_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
    or p_item_id <> 'raceChangeSelector'
    or p_target_card_id is null or length(trim(p_target_card_id)) < 1 or length(p_target_card_id) > 80
    or p_race not in ('저그', '테란', '프로토스') then
    return public.gacha_s2_command_error(p_idempotency_key, 'VALIDATION_FAILED', '종족 변경 요청이 올바르지 않습니다.', greatest(coalesce(p_expected_revision, 0), 0), null, null);
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'purchaseFixedSupportItem', 'expectedRevision', p_expected_revision,
    'itemId', p_item_id, 'targetCardId', p_target_card_id, 'race', p_race
  )::text, 'sha256'), 'hex');

  select revision, points into v_revision, v_points
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태가 없습니다.', 0, null, null); end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'purchaseFixedSupportItem' then
      return public.gacha_s2_command_error(p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '동일 요청 키를 재사용할 수 없습니다.', v_revision, null, null);
    end if;
    return v_previous.response;
  end if;
  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(p_idempotency_key, 'VERSION_CONFLICT', '최신 상태를 다시 불러와야 합니다.', v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null);
  end if;

  select coalesce(owned.race_override, catalog.race)
  into v_previous_race
  from public.gacha_s2_player_cards owned
  join public.gacha_s2_card_catalog catalog on catalog.card_id = owned.card_id
  where owned.user_id = p_user_id and owned.card_id = p_target_card_id
    and owned.copies > 0 and catalog.rarity <> 'EX' and not catalog.is_group
  for update of owned;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '보유 중인 전투 카드만 변경할 수 있습니다.', v_revision, null, null);
  end if;
  if p_race = v_previous_race then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '현재 종족과 다른 종족을 선택해 주세요.', v_revision, null, null);
  end if;

  select credits into v_credit
  from public.gacha_s2_race_selector_credits
  where user_id = p_user_id
  for update;
  v_credit := coalesce(v_credit, 0);

  select config into v_config from public.gacha_s2_balance_versions where active;
  v_product := v_config->'directSupportItems'->p_item_id;
  v_price := coalesce((v_product->>'price')::integer, 0);
  if v_product is null or v_price <> 20000000 then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '판매 설정을 불러오지 못했습니다.', v_revision, null, null);
  end if;
  if v_credit <= 0 and v_points < v_price then
    return public.gacha_s2_command_error(p_idempotency_key, 'COMMAND_REJECTED', '포인트가 부족합니다.', v_revision, null, null);
  end if;

  update public.gacha_s2_player_cards
  set race_override = p_race, updated_at = now()
  where user_id = p_user_id and card_id = p_target_card_id;

  if v_credit > 0 then
    update public.gacha_s2_race_selector_credits
    set credits = credits - 1, updated_at = now()
    where user_id = p_user_id;
  end if;

  update public.gacha_s2_player_states
  set points = points - case when v_credit > 0 then 0 else v_price end,
      shop_transactions = shop_transactions + case when v_credit > 0 then 0 else 1 end,
      revision = revision + 1,
      updated_at = now()
  where user_id = p_user_id
  returning revision into v_revision;

  v_snapshot := public.gacha_s2_get_player_snapshot(p_user_id);
  v_response := jsonb_build_object(
    'contractVersion', 1, 'ok', true, 'commandId', p_idempotency_key, 'idempotencyKey', p_idempotency_key,
    'revision', v_revision, 'serverTime', public.gacha_s2_now_ms(), 'serverSeed', null,
    'snapshot', v_snapshot,
    'result', jsonb_build_object(
      'itemId', p_item_id, 'cardId', p_target_card_id, 'previousRace', v_previous_race,
      'race', p_race, 'spentPoints', case when v_credit > 0 then 0 else v_price end,
      'appliedImmediately', true
    )
  );
  insert into public.gacha_s2_idempotency (user_id, idempotency_key, command_type, request_hash, response, expires_at)
  values (p_user_id, p_idempotency_key, 'purchaseFixedSupportItem', v_request_hash, v_response, now() + interval '24 hours');
  insert into public.gacha_s2_command_audit (user_id, command_id, command_type, request_hash, expected_revision, committed_revision, server_seed)
  values (p_user_id, p_idempotency_key, 'purchaseFixedSupportItem', v_request_hash, p_expected_revision, v_revision, null);
  return v_response;
end;
$$;

revoke all on function public.gacha_s2_purchase_fixed_support_item(uuid, bigint, text, text, text, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_purchase_fixed_support_item(uuid, bigint, text, text, text, text) to service_role;
drop function if exists public.gacha_s2_purchase_fixed_support_item(uuid, bigint, text, text);

do $verify$
declare
  v_config jsonb;
  v_snapshot_source text;
begin
  select config into v_config from public.gacha_s2_balance_versions where active;
  v_snapshot_source := pg_get_functiondef('public.gacha_s2_get_player_snapshot(uuid)'::regprocedure);
  if (v_config->'directSupportItems'->'raceChangeSelector'->>'price')::integer <> 20000000
    or v_config->'supportItems' ? 'raceChangeSelector'
    or v_snapshot_source not like '%c.race_override%'
    or to_regprocedure('public.gacha_s2_purchase_fixed_support_item(uuid,bigint,text,text,text,text)') is null
    or to_regprocedure('public.gacha_s2_purchase_fixed_support_item(uuid,bigint,text,text)') is not null
    or exists (select 1 from public.gacha_s2_player_states where support_items ? 'raceChangeSelector') then
    raise exception 'atomic race change selector verification failed';
  end if;
end;
$verify$;

commit;
