-- card-gacha 7차 마이그레이션: 카드 합성 시스템
-- Supabase 콘솔 > SQL Editor 에 붙여넣고 실행하세요. (점검 모드 중 실행 권장)
-- 여러 번 실행해도 안전합니다(idempotent). 기존 데이터는 건드리지 않습니다.
--
-- 합성 원자적 커밋 RPC. 재료 3장 차감 + (성공)결과카드 지급/점수 or (실패)위로 포인트.
-- 성공/실패 판정과 결과카드 선정은 서버(api/fuse.js, secureRandom)에서 끝내고,
-- 이 함수는 open-pack/dismantle 과 동일하게 "검증 + 원자적 커밋" 만 담당한다.

create or replace function public.gacha_fuse(
  p_user_id uuid,
  p_consume jsonb,          -- [{card_id, expected_count, new_count}] 재료별 차감(각 카드 1장 보존)
  p_success boolean,
  p_result_card_id text,    -- 성공 시 지급 카드 id (실패 시 null)
  p_points_gain integer,    -- 실패 위로 포인트 (성공 시 0)
  p_score_gain integer      -- 성공 시 랭킹 점수 가산 (신규 카드 가치, 실패 시 0)
) returns table(points integer, ranking_score integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user public.gacha_users%rowtype;
  v_item record;
  v_actual integer;
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
  end loop;

  -- 성공: 결과카드 +1 (신규면 insert, 보유중이면 count+1)
  if p_success then
    insert into public.gacha_collection(user_id, card_id, count)
    values (p_user_id, p_result_card_id, 1)
    on conflict (user_id, card_id) do update
    set count = public.gacha_collection.count + 1;
  end if;

  return query
  update public.gacha_users
  set points = public.gacha_users.points + p_points_gain,
      ranking_score = coalesce(public.gacha_users.ranking_score, 0) + p_score_gain
  where id = p_user_id
  returning public.gacha_users.points, public.gacha_users.ranking_score;
end;
$$;

revoke all on function public.gacha_fuse(uuid, jsonb, boolean, text, integer, integer) from public;
grant execute on function public.gacha_fuse(uuid, jsonb, boolean, text, integer, integer) to service_role;
