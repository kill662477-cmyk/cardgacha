-- 전 계정에 SSS 카드 선택권 2장 + 30만 포인트 지급.
-- 기록용 스냅샷 테이블을 남겨 중복 실행과 사후 추적을 막는다
-- (20260804002645_grant_trait_reroll_all_accounts_20260803.sql 과 같은 방식).
create table if not exists public.gacha_s2_sss_selector_grant_20260810 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  selector_before integer not null,
  selector_after integer not null,
  points_before bigint not null,
  points_after bigint not null,
  granted_at timestamptz not null default now()
);

with target as (
  select p.user_id,
         coalesce((p.support_items->>'sssCardSelector')::integer, 0) as selector_before,
         p.points as points_before
  from public.gacha_s2_player_states p
  where not exists (
    select 1 from public.gacha_s2_sss_selector_grant_20260810 g where g.user_id = p.user_id
  )
),
applied as (
  update public.gacha_s2_player_states p
  set support_items = jsonb_set(
        p.support_items,
        array['sssCardSelector'],
        to_jsonb(t.selector_before + 2),
        true
      ),
      points = p.points + 300000,
      revision = p.revision + 1,
      updated_at = now()
  from target t
  where p.user_id = t.user_id
  returning p.user_id, t.selector_before, t.points_before,
            (p.support_items->>'sssCardSelector')::integer as selector_after,
            p.points as points_after
)
insert into public.gacha_s2_sss_selector_grant_20260810 (
  user_id, selector_before, selector_after, points_before, points_after
)
select user_id, selector_before, selector_after, points_before, points_after from applied;

do $$
declare
  v_states integer;
  v_granted integer;
  v_bad_selector integer;
  v_bad_points integer;
begin
  select count(*) into v_states from public.gacha_s2_player_states;
  select count(*) into v_granted from public.gacha_s2_sss_selector_grant_20260810;
  if v_granted <> v_states then
    raise exception 'grant coverage mismatch: % granted vs % states', v_granted, v_states;
  end if;

  select count(*) into v_bad_selector
  from public.gacha_s2_sss_selector_grant_20260810
  where selector_after <> selector_before + 2;
  if v_bad_selector > 0 then
    raise exception 'selector delta wrong on % rows', v_bad_selector;
  end if;

  select count(*) into v_bad_points
  from public.gacha_s2_sss_selector_grant_20260810
  where points_after <> points_before + 300000;
  if v_bad_points > 0 then
    raise exception 'points delta wrong on % rows', v_bad_points;
  end if;
end;
$$;
