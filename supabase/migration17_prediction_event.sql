-- 캄몬 시빌워 승자예측 이벤트.
-- Supabase SQL Editor에서 실행. 여러 번 실행해도 안전합니다.

create table if not exists public.gacha_prediction_events (
  id text primary key,
  title text not null,
  options jsonb not null check (jsonb_typeof(options) = 'array'),
  reward_points integer not null check (reward_points > 0),
  closes_at timestamptz not null,
  winning_option text,
  settled_at timestamptz,
  created_at timestamptz default now()
);

create table if not exists public.gacha_prediction_votes (
  event_id text not null references public.gacha_prediction_events(id) on delete cascade,
  user_id uuid not null references public.gacha_users(id) on delete cascade,
  option text not null,
  created_at timestamptz default now(),
  primary key (event_id, user_id)
);

alter table public.gacha_prediction_events enable row level security;
alter table public.gacha_prediction_votes enable row level security;

create index if not exists idx_gacha_prediction_votes_event_option
  on public.gacha_prediction_votes (event_id, option);

insert into public.gacha_prediction_events (id, title, options, reward_points, closes_at)
values (
  'cammon-civil-war-2026-07-14',
  '캄몬 시빌워 승자예측 이벤트',
  '["변현제팀","김민철팀"]'::jsonb,
  3000,
  '2026-07-14 19:30:00+09'::timestamptz
)
on conflict (id) do update
set title = excluded.title,
    options = excluded.options,
    reward_points = excluded.reward_points,
    closes_at = excluded.closes_at
where public.gacha_prediction_events.settled_at is null;

create or replace function public.gacha_settle_prediction_event(
  p_event_id text,
  p_winning_option text
) returns table(event_id text, awarded_count integer, reward_points integer, already_settled boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event public.gacha_prediction_events%rowtype;
  v_awarded integer;
begin
  select * into v_event
  from public.gacha_prediction_events
  where id = p_event_id
  for update;

  if not found then
    raise exception 'prediction event not found';
  end if;

  if not exists (
    select 1
    from jsonb_array_elements_text(v_event.options) opt(value)
    where opt.value = p_winning_option
  ) then
    raise exception 'invalid winning option';
  end if;

  if v_event.settled_at is not null then
    return query select v_event.id, 0, v_event.reward_points, true;
    return;
  end if;

  update public.gacha_prediction_events
  set winning_option = p_winning_option,
      settled_at = now()
  where id = p_event_id;

  update public.gacha_users u
  set points = u.points + v_event.reward_points
  where exists (
    select 1
    from public.gacha_prediction_votes v
    where v.event_id = p_event_id
      and v.user_id = u.id
      and v.option = p_winning_option
  );
  get diagnostics v_awarded = row_count;

  return query select v_event.id, v_awarded, v_event.reward_points, false;
end;
$$;

revoke all on function public.gacha_settle_prediction_event(text, text) from public;
grant execute on function public.gacha_settle_prediction_event(text, text) to service_role;
