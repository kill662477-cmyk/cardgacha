-- card-gacha 10차 마이그레이션: SOOP 별풍선 포인트 브리지
-- SOOP ChatSDK 브리지에서 받은 이벤트를 한 번만 처리하고, 후원 시점에 존재하는 양쪽 계정에 별풍선 수량만큼 P를 지급한다.

create table if not exists public.gacha_soop_donation_events (
  event_id text primary key,
  sender_soop_id text not null,
  recipient_soop_id text not null,
  amount integer not null check (amount > 0),
  created_at timestamptz not null default now()
);

alter table public.gacha_soop_donation_events enable row level security;

-- 이전 초안에서 보류 포인트를 만들었다면 폐기한다. 미가입 계정에는 후원 포인트를 적립하지 않는다.
drop function if exists public.gacha_redeem_soop_pending_points(uuid, text);
drop table if exists public.gacha_soop_pending_points;

create or replace function public.gacha_apply_soop_donation(
  p_event_id text,
  p_sender_soop_id text,
  p_recipient_soop_id text,
  p_amount integer
) returns table(applied boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inserted text;
  v_sender_user uuid;
  v_recipient_user uuid;
  v_sender_exists boolean := false;
begin
  if length(trim(p_event_id)) < 8 or length(trim(p_event_id)) > 255
    or length(trim(p_sender_soop_id)) < 1 or length(trim(p_sender_soop_id)) > 100
    or length(trim(p_recipient_soop_id)) < 1 or length(trim(p_recipient_soop_id)) > 100
    or p_amount < 1 or p_amount > 100000 then
    raise exception 'invalid donation input';
  end if;

  -- 같은 두 계정의 동시 후원은 항상 같은 순서로 잠가 교착 상태를 피한다.
  perform pg_advisory_xact_lock(hashtext(least(p_sender_soop_id, p_recipient_soop_id)));
  if p_sender_soop_id <> p_recipient_soop_id then
    perform pg_advisory_xact_lock(hashtext(greatest(p_sender_soop_id, p_recipient_soop_id)));
  end if;

  insert into public.gacha_soop_donation_events(event_id, sender_soop_id, recipient_soop_id, amount)
  values (p_event_id, p_sender_soop_id, p_recipient_soop_id, p_amount)
  on conflict (event_id) do nothing
  returning event_id into v_inserted;

  if v_inserted is null then
    return query select false;
    return;
  end if;

  select id into v_sender_user from public.gacha_users where soop_id = p_sender_soop_id for update;
  v_sender_exists := found;
  if v_sender_exists then
    update public.gacha_users set points = public.gacha_users.points + p_amount where id = v_sender_user;
  end if;

  if p_recipient_soop_id = p_sender_soop_id then
    if v_sender_exists then
      update public.gacha_users set points = public.gacha_users.points + p_amount where id = v_sender_user;
    end if;
  else
    select id into v_recipient_user from public.gacha_users where soop_id = p_recipient_soop_id for update;
    if found then
      update public.gacha_users set points = public.gacha_users.points + p_amount where id = v_recipient_user;
    end if;
  end if;

  return query select true;
end;
$$;

revoke all on function public.gacha_apply_soop_donation(text, text, text, integer) from public;
grant execute on function public.gacha_apply_soop_donation(text, text, text, integer) to service_role;
