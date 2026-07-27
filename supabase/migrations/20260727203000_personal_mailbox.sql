-- Replace the static global mailbox modal with an account-scoped mailbox.
-- Reward migrations can call gacha_s2_deliver_mail() after a successful grant.

create table if not exists public.gacha_s2_mailbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  event_key text not null check (length(event_key) between 1 and 160),
  category text not null default 'SYSTEM' check (category in ('SYSTEM', 'REWARD', 'EVENT')),
  title text not null check (length(title) between 1 and 160),
  body text not null check (length(body) between 1 and 2000),
  points integer not null default 0 check (points between 0 and 100000000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (user_id, event_key)
);

create index if not exists idx_gacha_s2_mailbox_user_created
  on public.gacha_s2_mailbox(user_id, created_at desc);

create index if not exists idx_gacha_s2_mailbox_user_unread
  on public.gacha_s2_mailbox(user_id, created_at desc)
  where read_at is null;

alter table public.gacha_s2_mailbox enable row level security;
revoke all on table public.gacha_s2_mailbox from public, anon, authenticated;
grant select, insert, update on table public.gacha_s2_mailbox to service_role;

create or replace function public.gacha_s2_deliver_mail(
  p_user_id uuid,
  p_event_key text,
  p_title text,
  p_body text,
  p_category text default 'SYSTEM',
  p_points integer default 0
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_mail_id uuid;
begin
  if p_user_id is null
    or p_event_key is null or length(trim(p_event_key)) not between 1 and 160
    or p_title is null or length(trim(p_title)) not between 1 and 160
    or p_body is null or length(trim(p_body)) not between 1 and 2000
    or p_category not in ('SYSTEM', 'REWARD', 'EVENT')
    or p_points is null or p_points < 0 or p_points > 100000000
  then
    raise exception 'invalid mailbox payload';
  end if;

  insert into public.gacha_s2_mailbox (
    user_id, event_key, category, title, body, points
  )
  values (
    p_user_id, trim(p_event_key), p_category, trim(p_title), trim(p_body), p_points
  )
  on conflict (user_id, event_key) do nothing
  returning id into v_mail_id;

  if v_mail_id is null then
    select id into v_mail_id
    from public.gacha_s2_mailbox
    where user_id = p_user_id and event_key = trim(p_event_key);
  end if;

  return v_mail_id;
end;
$$;

create or replace function public.gacha_s2_get_mailbox(
  p_user_id uuid,
  p_limit integer default 50
)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  with selected as (
    select id, event_key, category, title, body, points, created_at, read_at
    from public.gacha_s2_mailbox
    where user_id = p_user_id
    order by created_at desc, id desc
    limit least(greatest(coalesce(p_limit, 50), 1), 100)
  )
  select jsonb_build_object(
    'ok', true,
    'unreadCount', (
      select count(*)::integer
      from public.gacha_s2_mailbox
      where user_id = p_user_id and read_at is null
    ),
    'messages', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', id,
          'eventKey', event_key,
          'category', category,
          'title', title,
          'body', body,
          'points', points,
          'createdAt', created_at,
          'readAt', read_at
        )
        order by created_at desc, id desc
      )
      from selected
    ), '[]'::jsonb)
  );
$$;

create or replace function public.gacha_s2_mark_mail_read(
  p_user_id uuid,
  p_mail_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_read_at timestamptz;
  v_unread integer;
begin
  update public.gacha_s2_mailbox
  set read_at = coalesce(read_at, now())
  where user_id = p_user_id and id = p_mail_id
  returning read_at into v_read_at;

  if v_read_at is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'MAIL_NOT_FOUND',
      'message', '우편을 찾을 수 없습니다.'
    );
  end if;

  select count(*)::integer into v_unread
  from public.gacha_s2_mailbox
  where user_id = p_user_id and read_at is null;

  return jsonb_build_object(
    'ok', true,
    'mailId', p_mail_id,
    'readAt', v_read_at,
    'unreadCount', v_unread
  );
end;
$$;

revoke all on function public.gacha_s2_deliver_mail(uuid, text, text, text, text, integer)
  from public, anon, authenticated;
revoke all on function public.gacha_s2_get_mailbox(uuid, integer)
  from public, anon, authenticated;
revoke all on function public.gacha_s2_mark_mail_read(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.gacha_s2_deliver_mail(uuid, text, text, text, text, integer)
  to service_role;
grant execute on function public.gacha_s2_get_mailbox(uuid, integer)
  to service_role;
grant execute on function public.gacha_s2_mark_mail_read(uuid, uuid)
  to service_role;

do $verify$
begin
  if to_regclass('public.gacha_s2_mailbox') is null then
    raise exception 'personal mailbox table missing';
  end if;
  if to_regprocedure('public.gacha_s2_deliver_mail(uuid,text,text,text,text,integer)') is null
    or to_regprocedure('public.gacha_s2_get_mailbox(uuid,integer)') is null
    or to_regprocedure('public.gacha_s2_mark_mail_read(uuid,uuid)') is null
  then
    raise exception 'personal mailbox functions missing';
  end if;
end
$verify$;
