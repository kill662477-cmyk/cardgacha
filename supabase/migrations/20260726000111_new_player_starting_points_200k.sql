-- 신규 가입자 시작 포인트 5,000 -> 200,000 으로 상향 + 최근 가입자 소급 지급.
--
-- 배경: 월드보스·모험 보상이 커지면서 5,000 포인트로 시작하는 신규 가입자가
-- 기존 유저를 따라잡기 어려워졌다.
--
-- 두 가지를 한다.
--   1) 2026-07-24 00:00 KST 이후 가입한 계정에 200,000 포인트 소급 지급
--   2) gacha_s2_player_states.points 기본값을 200,000 으로 변경(앞으로의 가입자)
--
-- 2)만으로 충분한 이유: 신규 가입 경로(gacha_s2_consume_soop_auth_exchange)는
-- `insert into gacha_s2_player_states (user_id)` 로 points 를 명시하지 않아
-- 컬럼 기본값을 그대로 쓴다. 시즌1 이관 스크립트만 points 를 직접 지정하는데
-- 그건 이미 실행이 끝난 1회성 마이그레이션이라 영향이 없다.
--
-- 지급은 전용 테이블로 멱등성을 보장한다(50,000 전체 지급 때와 같은 방식).
-- 이미 지급된 계정은 points_after 가 채워져 있어 재실행해도 두 번 지급되지 않는다.

lock table public.gacha_s2_player_states in share row exclusive mode;

create table if not exists public.gacha_s2_new_player_reward_20260726 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  points_granted integer not null default 200000,
  points_before integer,
  points_after integer,
  created_at timestamptz not null default now()
);

-- 대상: 2026-07-24 00:00 KST 이후 생성된 계정.
insert into public.gacha_s2_new_player_reward_20260726 (user_id, points_before)
select a.id, s.points
from public.gacha_s2_accounts a
join public.gacha_s2_player_states s on s.user_id = a.id
where a.created_at >= timestamptz '2026-07-24 00:00:00+09'
on conflict (user_id) do nothing;

update public.gacha_s2_player_states state
set points = state.points + reward.points_granted,
    updated_at = now()
from public.gacha_s2_new_player_reward_20260726 reward
where reward.user_id = state.user_id
  and reward.points_after is null;

update public.gacha_s2_new_player_reward_20260726 reward
set points_after = state.points
from public.gacha_s2_player_states state
where state.user_id = reward.user_id
  and reward.points_after is null;

do $$
declare
  v_count integer;
  v_bad integer;
begin
  select count(*) into v_count from public.gacha_s2_new_player_reward_20260726;
  -- 지급 전후 차이가 정확히 200,000 인지 전수 확인한다.
  select count(*) into v_bad
  from public.gacha_s2_new_player_reward_20260726
  where points_after is null or points_after - points_before <> points_granted;
  if v_bad > 0 then
    raise exception 'new player reward mismatch on % of % rows', v_bad, v_count;
  end if;
  raise notice 'new player reward granted to % accounts', v_count;
end;
$$;

-- 앞으로 가입하는 계정은 200,000 으로 시작한다.
alter table public.gacha_s2_player_states alter column points set default 200000;

do $$
begin
  if (select column_default from information_schema.columns
      where table_schema = 'public' and table_name = 'gacha_s2_player_states'
        and column_name = 'points') <> '200000' then
    raise exception 'starting points default not applied';
  end if;
end;
$$;

alter table public.gacha_s2_new_player_reward_20260726 enable row level security;
revoke all on table public.gacha_s2_new_player_reward_20260726 from public, anon, authenticated;
