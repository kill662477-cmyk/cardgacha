-- 가드 창을 15초 -> 60초로 넓힌다.
--
-- 15초 가드 적용 뒤에도 29초 간격으로 같은 카드가 두 장 들어간 사례가 한 건 남았다.
-- 버그 패턴(평균 4.8초)과는 다르지만 단정할 수 없어, 창을 넉넉히 잡아 확실히 덮는다.
--
-- 같은 카드를 일부러 여러 장 모으는 것(SSS 강화 재료)은 정당한 플레이다. 다만 1분을
-- 두고 다시 고르면 되므로 실질 제약은 거의 없다. 다른 카드를 고르는 것은 계속 자유다.
do $$
declare v_src text;
begin
  v_src := pg_get_functiondef('public.gacha_s2_redeem_card_selector(uuid,bigint,text,text,text)'::regprocedure);

  if v_src not like '%interval ''15 seconds''%' then
    raise exception '15s guard window not found';
  end if;
  v_src := replace(v_src, 'interval ''15 seconds''', 'interval ''60 seconds''');

  if v_src not like '%interval ''60 seconds''%' then
    raise exception 'widened window not applied';
  end if;
  if position('card_selector_recent' in v_src) > position('insert into public.gacha_s2_player_cards' in v_src) then
    raise exception 'guard must run before the card is granted';
  end if;
  execute v_src;
end;
$$;

-- 15초 가드가 놓친 구간(10:45:22 ~ 지금)에서 같은 카드가 두 장 들어간 계정에도 보상한다.
with late_victims as (
  select distinct pc.user_id
  from public.gacha_s2_player_cards pc
  where pc.first_acquired_at >= '2026-08-10 10:45:22+00'
    and pc.copies >= 2
    and exists (
      select 1 from public.gacha_s2_command_audit r
      where r.user_id = pc.user_id
        and r.command_type = 'redeemCardSelector'
        and r.created_at = pc.first_acquired_at
    )
    and not exists (
      select 1 from public.gacha_s2_sss_selector_victim_grant_20260810 g where g.user_id = pc.user_id
    )
),
target as (
  select v.user_id, coalesce((p.support_items->>'sssCardSelector')::integer, 0) as selector_before
  from late_victims v
  join public.gacha_s2_player_states p on p.user_id = v.user_id
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
  returning p.user_id, t.selector_before,
            (p.support_items->>'sssCardSelector')::integer as selector_after
)
insert into public.gacha_s2_sss_selector_victim_grant_20260810 (
  user_id, double_spend_count, selector_before, selector_after
)
select user_id, 1, selector_before, selector_after from applied;

do $$
declare v_src text; v_bad integer;
begin
  v_src := pg_get_functiondef('public.gacha_s2_redeem_card_selector(uuid,bigint,text,text,text)'::regprocedure);
  if v_src like '%interval ''15 seconds''%' then
    raise exception 'old 15s window survived';
  end if;
  if v_src not like '%보유하지 않은 카드 선택권입니다%'
     or v_src not like '%등급 카드만 선택할 수 있습니다%'
     or v_src not like '%IDEMPOTENCY_KEY_REUSED%' then
    raise exception 'existing checks lost';
  end if;
  select count(*) into v_bad
  from public.gacha_s2_sss_selector_victim_grant_20260810
  where selector_after <> selector_before + 1;
  if v_bad > 0 then raise exception 'grant delta wrong on % rows', v_bad; end if;
end;
$$;
