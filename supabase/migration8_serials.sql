-- card-gacha 8차 마이그레이션: 카드 넘버링(시리얼) 시스템
-- Supabase 콘솔 > SQL Editor 에 붙여넣고 실행하세요. (점검 모드 중 실행 권장)
-- 여러 번 실행해도 안전합니다(idempotent).
--
-- 카드가 발행될 때마다(팩 뽑기 / 합성 성공) card_id 별 글로벌 발행 순번(serial)을 부여한다.
-- 유저는 자기가 보유한 각 장의 시리얼을 소유한다.
-- 재료 소모(합성 / 분해) 시에는 해당 유저·카드의 "가장 큰(최신)" 시리얼부터 삭제한다.
--   → 낮은 번호(초기 발행)일수록 소장가치가 높으므로 보존된다.
-- 주의: 기존 보유 카드(시리얼 없는 count)는 백필하지 않는다. 16시 전계정 초기화 후 빈 상태에서 시작.

-- ============================================================
-- 1. 테이블
-- ============================================================
create table if not exists gacha_card_counters (
  card_id text primary key,
  issued bigint not null default 0
);
create table if not exists gacha_card_serials (
  id bigint generated always as identity primary key,
  user_id uuid not null references gacha_users(id) on delete cascade,
  card_id text not null,
  serial bigint not null,
  acquired_via text not null default 'pack',
  created_at timestamptz default now(),
  unique(card_id, serial)
);
create index if not exists idx_serials_user on gacha_card_serials(user_id, card_id);
alter table gacha_card_counters enable row level security;
alter table gacha_card_serials enable row level security;
-- (정책 미생성 = anon 전면 차단, service_role 만 통과)

-- ============================================================
-- 2. gacha_open_pack 확장 (시리얼 발행 + serials jsonb 반환)
--    반환 컬럼이 추가되므로 create or replace 로는 타입 변경이 불가 → drop 후 재생성.
-- ============================================================
drop function if exists public.gacha_open_pack(uuid, integer, integer, jsonb);

create or replace function public.gacha_open_pack(
  p_user_id uuid,
  p_price integer,
  p_score_gain integer,
  p_gains jsonb
) returns table(points integer, ranking_score integer, serials jsonb)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user public.gacha_users%rowtype;
  v_card_id text;
  v_delta_text text;
  v_delta integer;
  v_issued_hi bigint;
  v_serials jsonb := '{}'::jsonb;
begin
  if p_price < 1 or p_score_gain < 0 or jsonb_typeof(p_gains) <> 'object' then
    raise exception 'invalid pack input';
  end if;

  select * into v_user from public.gacha_users where id = p_user_id for update;
  if not found then raise exception 'user not found'; end if;
  if v_user.points < p_price then raise exception 'insufficient points' using errcode = 'P0001'; end if;

  for v_card_id, v_delta_text in select key, value from jsonb_each_text(p_gains) loop
    v_delta := v_delta_text::integer;
    if v_delta < 1 then raise exception 'invalid card gain'; end if;
    insert into public.gacha_collection(user_id, card_id, count)
    values (p_user_id, v_card_id, v_delta)
    on conflict (user_id, card_id) do update
    set count = public.gacha_collection.count + excluded.count;

    -- 시리얼 발행: 카운터를 v_delta 만큼 원자 증가 → 마지막 번호 = v_issued_hi.
    -- 이번 콜에서 발행된 번호 범위 = [v_issued_hi - v_delta + 1 .. v_issued_hi]
    insert into public.gacha_card_counters(card_id, issued)
    values (v_card_id, v_delta)
    on conflict (card_id) do update
    set issued = public.gacha_card_counters.issued + excluded.issued
    returning issued into v_issued_hi;

    insert into public.gacha_card_serials(user_id, card_id, serial, acquired_via)
    select p_user_id, v_card_id, gs, 'pack'
    from generate_series(v_issued_hi - v_delta + 1, v_issued_hi) gs;

    v_serials := v_serials || jsonb_build_object(
      v_card_id,
      to_jsonb(array(select generate_series(v_issued_hi - v_delta + 1, v_issued_hi)))
    );
  end loop;

  return query
  update public.gacha_users
  set points = public.gacha_users.points - p_price,
      ranking_score = coalesce(public.gacha_users.ranking_score, 0) + p_score_gain
  where id = p_user_id
  returning public.gacha_users.points, public.gacha_users.ranking_score, v_serials;
end;
$$;

-- ============================================================
-- 3. gacha_fuse 확장 (재료 최신 시리얼 삭제 + 성공 시 결과 시리얼 발행/반환)
--    반환 컬럼 추가 → drop 후 재생성.
-- ============================================================
drop function if exists public.gacha_fuse(uuid, jsonb, boolean, text, integer, integer);

create or replace function public.gacha_fuse(
  p_user_id uuid,
  p_consume jsonb,          -- [{card_id, expected_count, new_count}] 재료별 차감(각 카드 1장 보존)
  p_success boolean,
  p_result_card_id text,    -- 성공 시 지급 카드 id (실패 시 null)
  p_points_gain integer,    -- 실패 위로 포인트 (성공 시 0)
  p_score_gain integer      -- 성공 시 랭킹 점수 가산 (신규 카드 가치, 실패 시 0)
) returns table(points integer, ranking_score integer, serial bigint)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user public.gacha_users%rowtype;
  v_item record;
  v_actual integer;
  v_result_serial bigint;
begin
  if jsonb_typeof(p_consume) <> 'array' or jsonb_array_length(p_consume) < 1 then
    raise exception 'invalid fuse input';
  end if;
  if p_points_gain < 0 or p_score_gain < 0 then
    raise exception 'invalid fuse input';
  end if;
  if p_success and (p_result_card_id is null or length(p_result_card_id) < 1) then
    raise exception 'invalid fuse input';
  end if;

  select * into v_user from public.gacha_users where id = p_user_id for update;
  if not found then raise exception 'user not found'; end if;

  -- 재료 차감: 각 카드 현재 수량이 expected 와 일치하는지 확인 후 new_count 로 설정.
  -- new_count >= 1 (최소 1장 보존), new_count < expected (반드시 감소).
  for v_item in
    select * from jsonb_to_recordset(p_consume)
      as x(card_id text, expected_count integer, new_count integer)
  loop
    if v_item.card_id is null or v_item.expected_count is null or v_item.new_count is null
      or v_item.expected_count < 2 or v_item.new_count < 1 or v_item.new_count >= v_item.expected_count then
      raise exception 'invalid fuse input';
    end if;
    select count into v_actual from public.gacha_collection
    where user_id = p_user_id and card_id = v_item.card_id for update;
    if not found or v_actual <> v_item.expected_count then
      raise exception 'state changed' using errcode = 'P0001';
    end if;
    update public.gacha_collection set count = v_item.new_count
    where user_id = p_user_id and card_id = v_item.card_id;

    -- 소모분 만큼 "가장 큰 시리얼"부터 삭제(낮은 번호=초기 발행 보존).
    delete from public.gacha_card_serials
    where id in (
      select id from public.gacha_card_serials
      where user_id = p_user_id and card_id = v_item.card_id
      order by gacha_card_serials.serial desc
      limit (v_item.expected_count - v_item.new_count)
    );
  end loop;

  -- 성공: 결과카드 +1 (신규면 insert, 보유중이면 count+1) + 시리얼 발행
  if p_success then
    insert into public.gacha_collection(user_id, card_id, count)
    values (p_user_id, p_result_card_id, 1)
    on conflict (user_id, card_id) do update
    set count = public.gacha_collection.count + 1;

    insert into public.gacha_card_counters(card_id, issued)
    values (p_result_card_id, 1)
    on conflict (card_id) do update
    set issued = public.gacha_card_counters.issued + 1
    returning issued into v_result_serial;

    insert into public.gacha_card_serials(user_id, card_id, serial, acquired_via)
    values (p_user_id, p_result_card_id, v_result_serial, 'fuse');
  end if;

  return query
  update public.gacha_users
  set points = public.gacha_users.points + p_points_gain,
      ranking_score = coalesce(public.gacha_users.ranking_score, 0) + p_score_gain
  where id = p_user_id
  returning public.gacha_users.points, public.gacha_users.ranking_score, v_result_serial;
end;
$$;

-- ============================================================
-- 4. gacha_dismantle 확장 (재료 최신 시리얼 삭제)
--    반환 타입 변경 없음 → create or replace 그대로.
-- ============================================================
create or replace function public.gacha_dismantle(
  p_user_id uuid,
  p_updates jsonb
) returns table(points integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user public.gacha_users%rowtype;
  v_item record;
  v_actual integer;
  v_total integer := 0;
begin
  if jsonb_typeof(p_updates) <> 'array' or jsonb_array_length(p_updates) < 1 then
    raise exception 'invalid dismantle input';
  end if;

  select * into v_user from public.gacha_users where id = p_user_id for update;
  if not found then raise exception 'user not found'; end if;

  for v_item in
    select * from jsonb_to_recordset(p_updates)
      as x(card_id text, expected_count integer, new_count integer, refund integer)
  loop
    if v_item.card_id is null or v_item.expected_count is null or v_item.new_count is null or v_item.refund is null
      or v_item.expected_count < 2 or v_item.new_count < 1 or v_item.new_count >= v_item.expected_count or v_item.refund < 0 then
      raise exception 'invalid dismantle input';
    end if;
    select count into v_actual from public.gacha_collection
    where user_id = p_user_id and card_id = v_item.card_id for update;
    if not found or v_actual <> v_item.expected_count then
      raise exception 'state changed' using errcode = 'P0001';
    end if;
    update public.gacha_collection set count = v_item.new_count
    where user_id = p_user_id and card_id = v_item.card_id;
    v_total := v_total + v_item.refund;

    -- 분해분 만큼 "가장 큰 시리얼"부터 삭제(낮은 번호=초기 발행 보존).
    delete from public.gacha_card_serials
    where id in (
      select id from public.gacha_card_serials
      where user_id = p_user_id and card_id = v_item.card_id
      order by serial desc
      limit (v_item.expected_count - v_item.new_count)
    );
  end loop;

  return query
  update public.gacha_users set points = public.gacha_users.points + v_total where id = p_user_id
  returning public.gacha_users.points;
end;
$$;

-- ============================================================
-- 5. 권한 (drop 으로 사라진 grant 재설정)
-- ============================================================
revoke all on function public.gacha_open_pack(uuid, integer, integer, jsonb) from public;
revoke all on function public.gacha_fuse(uuid, jsonb, boolean, text, integer, integer) from public;
revoke all on function public.gacha_dismantle(uuid, jsonb) from public;
grant execute on function public.gacha_open_pack(uuid, integer, integer, jsonb) to service_role;
grant execute on function public.gacha_fuse(uuid, jsonb, boolean, text, integer, integer) to service_role;
grant execute on function public.gacha_dismantle(uuid, jsonb) to service_role;
