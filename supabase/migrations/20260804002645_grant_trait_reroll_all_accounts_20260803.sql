-- 전 계정에 랜덤특성변경권(traitReroll) 1장 지급.
-- 지급 사실을 우편/공지로 알리지 않는다(운영 요청). 인벤토리에만 조용히 반영된다.
-- 기록용 스냅샷 테이블을 남겨 중복 실행과 사후 추적을 막는다.
create table if not exists public.gacha_s2_trait_reroll_grant_20260803 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  before_count integer not null,
  after_count integer not null,
  granted_at timestamptz not null default now()
);

with target as (
  select p.user_id,
         coalesce((p.support_items->>'traitReroll')::integer, 0) as before_count
  from public.gacha_s2_player_states p
  where not exists (
    select 1 from public.gacha_s2_trait_reroll_grant_20260803 g where g.user_id = p.user_id
  )
),
applied as (
  update public.gacha_s2_player_states p
  set support_items = jsonb_set(
        p.support_items,
        array['traitReroll'],
        to_jsonb(t.before_count + 1),
        true
      ),
      revision = p.revision + 1,
      updated_at = now()
  from target t
  where p.user_id = t.user_id
  returning p.user_id, t.before_count, (p.support_items->>'traitReroll')::integer as after_count
)
insert into public.gacha_s2_trait_reroll_grant_20260803 (user_id, before_count, after_count)
select user_id, before_count, after_count from applied;

do $$
declare
  v_states integer;
  v_granted integer;
  v_bad integer;
begin
  select count(*) into v_states from public.gacha_s2_player_states;
  select count(*) into v_granted from public.gacha_s2_trait_reroll_grant_20260803;
  if v_granted <> v_states then
    raise exception 'trait reroll grant coverage mismatch: % granted vs % states', v_granted, v_states;
  end if;

  select count(*) into v_bad
  from public.gacha_s2_trait_reroll_grant_20260803
  where after_count <> before_count + 1;
  if v_bad > 0 then
    raise exception 'trait reroll grant delta wrong on % rows', v_bad;
  end if;
end;
$$;
