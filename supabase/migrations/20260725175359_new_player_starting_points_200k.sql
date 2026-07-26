lock table public.gacha_s2_player_states in share row exclusive mode;

create table if not exists public.gacha_s2_new_player_reward_20260726 (
  user_id uuid primary key references public.gacha_s2_accounts(id) on delete cascade,
  points_granted integer not null default 200000,
  points_before integer,
  points_after integer,
  created_at timestamptz not null default now()
);

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
  select count(*) into v_bad
  from public.gacha_s2_new_player_reward_20260726
  where points_after is null or points_after - points_before <> points_granted;
  if v_bad > 0 then
    raise exception 'new player reward mismatch on % of % rows', v_bad, v_count;
  end if;
  raise notice 'new player reward granted to % accounts', v_count;
end;
$$;

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
revoke all on table public.gacha_s2_new_player_reward_20260726 from public, anon, authenticated;;
