-- 전 계정에 SSS 카드 선택권 1장 추가 지급(오류 보상).
--
-- 오늘 지급한 선택권이 한 번 고르면 두 장이 써지는 문제가 있었다. 성공 후에도
-- 고른 카드와 확인 버튼이 살아 있어 결과창을 닫는 클릭/엔터가 같은 카드로 두 번째
-- 장을 즉시 소모했다. 선택권을 쓴 64계정 중 61계정에서 30초 안에 두 번째 실행이 찍혔다.
--
-- 클라이언트 수정 배포를 확인한 뒤 지급한다. 고치기 전에 주면 보상분도 같이 날아간다.
-- 피해 계정만이 아니라 전 계정에 지급한다(운영 요청).
create table if not exists public.gacha_s2_sss_selector_compensation_20260810 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  selector_before integer not null,
  selector_after integer not null,
  granted_at timestamptz not null default now()
);

with target as (
  select p.user_id,
         coalesce((p.support_items->>'sssCardSelector')::integer, 0) as selector_before
  from public.gacha_s2_player_states p
  where not exists (
    select 1 from public.gacha_s2_sss_selector_compensation_20260810 g where g.user_id = p.user_id
  )
),
applied as (
  update public.gacha_s2_player_states p
  set support_items = jsonb_set(
        p.support_items,
        array['sssCardSelector'],
        to_jsonb(t.selector_before + 1),
        true
      ),
      revision = p.revision + 1,
      updated_at = now()
  from target t
  where p.user_id = t.user_id
  returning p.user_id, t.selector_before,
            (p.support_items->>'sssCardSelector')::integer as selector_after
)
insert into public.gacha_s2_sss_selector_compensation_20260810 (user_id, selector_before, selector_after)
select user_id, selector_before, selector_after from applied;

do $$
declare
  v_states integer;
  v_granted integer;
  v_bad integer;
begin
  select count(*) into v_states from public.gacha_s2_player_states;
  select count(*) into v_granted from public.gacha_s2_sss_selector_compensation_20260810;
  if v_granted <> v_states then
    raise exception 'compensation coverage mismatch: % granted vs % states', v_granted, v_states;
  end if;

  select count(*) into v_bad
  from public.gacha_s2_sss_selector_compensation_20260810
  where selector_after <> selector_before + 1;
  if v_bad > 0 then
    raise exception 'compensation delta wrong on % rows', v_bad;
  end if;
end;
$$;
