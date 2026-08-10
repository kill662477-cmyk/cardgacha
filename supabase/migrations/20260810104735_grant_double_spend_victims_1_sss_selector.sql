-- 선택권 이중 소모 피해 계정에만 SSS 카드 선택권 1장 지급.
--
-- 피해 판정: 서버 가드가 걸리기 시작한 2026-08-10 10:45:22 이전에, 같은 계정에서
-- redeemCardSelector 가 15초 안에 연달아 실행된 경우. 사람이 카드를 다시 골라
-- 확인까지 누르는 데 15초는 걸린다. 실측 평균 간격은 4.8초였다.
create table if not exists public.gacha_s2_sss_selector_victim_grant_20260810 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  double_spend_count integer not null,
  selector_before integer not null,
  selector_after integer not null,
  granted_at timestamptz not null default now()
);

with victims as (
  select user_id, count(*)::integer as double_spend_count
  from (
    select user_id, created_at,
      created_at - lag(created_at) over (partition by user_id order by created_at) as gap
    from public.gacha_s2_command_audit
    where command_type = 'redeemCardSelector'
      and created_at >= '2026-08-10 10:05:00+00'
      and created_at < '2026-08-10 10:45:22+00'
  ) paired
  where gap < interval '15 seconds'
  group by user_id
),
target as (
  select v.user_id, v.double_spend_count,
         coalesce((p.support_items->>'sssCardSelector')::integer, 0) as selector_before
  from victims v
  join public.gacha_s2_player_states p on p.user_id = v.user_id
  where not exists (
    select 1 from public.gacha_s2_sss_selector_victim_grant_20260810 g where g.user_id = v.user_id
  )
),
applied as (
  update public.gacha_s2_player_states p
  set support_items = jsonb_set(
        p.support_items, array['sssCardSelector'],
        to_jsonb(t.selector_before + 1), true
      ),
      revision = p.revision + 1,
      updated_at = now()
  from target t
  where p.user_id = t.user_id
  returning p.user_id, t.double_spend_count, t.selector_before,
            (p.support_items->>'sssCardSelector')::integer as selector_after
)
insert into public.gacha_s2_sss_selector_victim_grant_20260810 (
  user_id, double_spend_count, selector_before, selector_after
)
select user_id, double_spend_count, selector_before, selector_after from applied;

do $$
declare
  v_expected integer;
  v_granted integer;
  v_bad integer;
begin
  select count(distinct user_id) into v_expected
  from (
    select user_id,
      created_at - lag(created_at) over (partition by user_id order by created_at) as gap
    from public.gacha_s2_command_audit
    where command_type = 'redeemCardSelector'
      and created_at >= '2026-08-10 10:05:00+00'
      and created_at < '2026-08-10 10:45:22+00'
  ) paired
  where gap < interval '15 seconds';

  select count(*) into v_granted from public.gacha_s2_sss_selector_victim_grant_20260810;
  if v_granted <> v_expected then
    raise exception 'victim coverage mismatch: % granted vs % expected', v_granted, v_expected;
  end if;

  select count(*) into v_bad
  from public.gacha_s2_sss_selector_victim_grant_20260810
  where selector_after <> selector_before + 1;
  if v_bad > 0 then
    raise exception 'victim grant delta wrong on % rows', v_bad;
  end if;
end;
$$;
