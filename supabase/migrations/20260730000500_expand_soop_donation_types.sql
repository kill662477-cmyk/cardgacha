-- Expand SOOP donation bridge coverage.
-- Official ChatSDK actions:
--   ADBALLOON_GIFTED    = 애드벌룬
--   VIDEOBALLOON_GIFTED = 영상풍선(영상도네이션)
-- Existing 1 donation unit = 30P rule and both-side crediting stay unchanged.

begin;

lock table public.gacha_s2_soop_donation_events in share row exclusive mode;

alter table public.gacha_s2_soop_donation_events
  drop constraint gacha_s2_soop_donation_events_action_check;

alter table public.gacha_s2_soop_donation_events
  add constraint gacha_s2_soop_donation_events_action_check
  check (
    action in (
      'BALLOON_GIFTED',
      'ADBALLOON_GIFTED',
      'VIDEOBALLOON_GIFTED',
      'BATTLE_MISSION_GIFTED'
    )
  );

create or replace function public.gacha_s2_apply_soop_donation(
  p_bridge_user_id uuid,
  p_event_id text,
  p_action text,
  p_sender_soop_id text,
  p_recipient_soop_id text,
  p_amount integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing public.gacha_s2_soop_donation_events%rowtype;
  v_sender_user uuid;
  v_recipient_user uuid;
  v_points integer;
begin
  if p_bridge_user_id is null
    or p_event_id is null or length(trim(p_event_id)) < 8 or length(trim(p_event_id)) > 255
    or p_action is null or p_action not in (
      'BALLOON_GIFTED',
      'ADBALLOON_GIFTED',
      'VIDEOBALLOON_GIFTED',
      'BATTLE_MISSION_GIFTED'
    )
    or p_sender_soop_id is null or length(trim(p_sender_soop_id)) < 1 or length(trim(p_sender_soop_id)) > 100
    or p_recipient_soop_id is null or length(trim(p_recipient_soop_id)) < 1 or length(trim(p_recipient_soop_id)) > 100
    or p_amount is null or p_amount < 1 or p_amount > 100000 then
    raise exception 'invalid donation input';
  end if;

  if not exists (
    select 1
    from public.gacha_s2_streamer_bridges bridge
    where bridge.user_id = p_bridge_user_id
      and bridge.soop_id = trim(p_recipient_soop_id)
      and bridge.active
  ) then
    raise exception 'bridge recipient mismatch';
  end if;

  perform pg_advisory_xact_lock(hashtext('gacha_s2_soop:' || p_event_id));
  perform pg_advisory_xact_lock(
    hashtext('gacha_s2_soop_user:' || least(p_sender_soop_id, p_recipient_soop_id))
  );
  if p_sender_soop_id <> p_recipient_soop_id then
    perform pg_advisory_xact_lock(
      hashtext('gacha_s2_soop_user:' || greatest(p_sender_soop_id, p_recipient_soop_id))
    );
  end if;

  select *
  into v_existing
  from public.gacha_s2_soop_donation_events
  where event_id = p_event_id;

  if found then
    if v_existing.action <> p_action
      or v_existing.sender_soop_id <> trim(p_sender_soop_id)
      or v_existing.recipient_soop_id <> trim(p_recipient_soop_id)
      or v_existing.amount <> p_amount then
      raise exception 'donation event id reused with different payload';
    end if;
    return jsonb_build_object(
      'applied', false,
      'pointsPerAccount', v_existing.points_per_account
    );
  end if;

  v_points := p_amount * 30;

  select id
  into v_sender_user
  from public.gacha_s2_accounts
  where soop_id = trim(p_sender_soop_id);

  select id
  into v_recipient_user
  from public.gacha_s2_accounts
  where soop_id = trim(p_recipient_soop_id);

  if v_sender_user is not null and v_sender_user = v_recipient_user then
    update public.gacha_s2_player_states
    set points = points + v_points * 2,
        revision = revision + 1,
        updated_at = now()
    where user_id = v_sender_user;
  else
    if v_sender_user is not null then
      update public.gacha_s2_player_states
      set points = points + v_points,
          revision = revision + 1,
          updated_at = now()
      where user_id = v_sender_user;
    end if;

    if v_recipient_user is not null then
      update public.gacha_s2_player_states
      set points = points + v_points,
          revision = revision + 1,
          updated_at = now()
      where user_id = v_recipient_user;
    end if;
  end if;

  insert into public.gacha_s2_soop_donation_events (
    event_id,
    action,
    sender_soop_id,
    recipient_soop_id,
    amount,
    points_per_account,
    sender_user_id,
    recipient_user_id,
    bridge_user_id
  ) values (
    trim(p_event_id),
    p_action,
    trim(p_sender_soop_id),
    trim(p_recipient_soop_id),
    p_amount,
    v_points,
    v_sender_user,
    v_recipient_user,
    p_bridge_user_id
  );

  return jsonb_build_object(
    'applied', true,
    'pointsPerAccount', v_points,
    'senderCredited', v_sender_user is not null,
    'recipientCredited', v_recipient_user is not null
  );
end;
$$;

revoke all on function public.gacha_s2_apply_soop_donation(
  uuid, text, text, text, text, integer
) from public, anon, authenticated;

grant execute on function public.gacha_s2_apply_soop_donation(
  uuid, text, text, text, text, integer
) to service_role;

do $verify$
declare
  v_constraint text;
  v_function text;
begin
  select pg_get_constraintdef(oid)
  into v_constraint
  from pg_constraint
  where conname = 'gacha_s2_soop_donation_events_action_check'
    and conrelid = 'public.gacha_s2_soop_donation_events'::regclass;

  if v_constraint is null
    or v_constraint not like '%''BALLOON_GIFTED''%'
    or v_constraint not like '%''ADBALLOON_GIFTED''%'
    or v_constraint not like '%''VIDEOBALLOON_GIFTED''%'
    or v_constraint not like '%''BATTLE_MISSION_GIFTED''%' then
    raise exception 'SOOP donation action constraint verification failed';
  end if;

  select pg_get_functiondef(
    'public.gacha_s2_apply_soop_donation(uuid,text,text,text,text,integer)'::regprocedure
  )
  into v_function;

  if v_function not like '%ADBALLOON_GIFTED%'
    or v_function not like '%VIDEOBALLOON_GIFTED%'
    or v_function not like '%v_points := p_amount * 30%' then
    raise exception 'SOOP donation function verification failed';
  end if;
end
$verify$;

commit;
