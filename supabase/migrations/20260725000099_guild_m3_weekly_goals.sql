-- 길드 M3: 주간 공동목표 (PDB-16 3.2)
--
-- 진행도를 따로 저장하지 않고 gacha_s2_guild_contributions 에서 집계한다.
-- 개인 기여 상한(목표의 8%)을 정확히 적용하려면 "누가 몇 번 했는지"가 필요한데,
-- 그 정보가 이미 이 테이블에 일별로 쌓이기 때문이다. 진행도 테이블을 따로 두면
-- 상한 계산용 개인 내역을 이중으로 관리해야 한다.
--
-- 주간 리셋은 배치(cron)가 없으므로 week_start_kst 를 키로 삼아 자연스럽게 갈린다.
-- 새 주가 되면 조회 대상 주차가 바뀌어 진행도가 0부터 시작한다.

-- GP 는 점수라 상한에 걸리면 횟수를 역산할 수 없다. 실제 수행 횟수를 따로 센다.
alter table public.gacha_s2_guild_contributions
  add column if not exists actions integer not null default 0 check (actions >= 0);

-- 해당 시각이 속한 주의 월요일(KST). date_trunc('week') 는 월요일 시작이다.
create or replace function public.gacha_s2_guild_week_start(p_now timestamptz default now())
returns date
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (date_trunc('week', (p_now at time zone 'Asia/Seoul')))::date;
$$;

-- 주간 보상 수령 기록. 달성 시 길드원 전원이 각자 수령한다.
create table if not exists public.gacha_s2_guild_weekly_claims (
  guild_id uuid not null references public.gacha_s2_guilds(guild_id) on delete cascade,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  week_start_kst date not null,
  points integer not null check (points >= 0 and points <= 200000),
  claimed_at timestamptz not null default now(),
  primary key (guild_id, week_start_kst, user_id)
);

-- 주간 목표 진행도. 목표치는 인원 비례(기준 30명), 1인 기여는 목표의 8% 까지만 집계한다.
create or replace function public.gacha_s2_guild_weekly_progress(
  p_guild_id uuid,
  p_week date default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_week date := coalesce(p_week, public.gacha_s2_guild_week_start());
  v_members integer;
  v_goals jsonb := '[]'::jsonb;
  v_all_complete boolean := true;
  v_goal record;
  v_target integer;
  v_cap integer;
  v_progress bigint;
begin
  select count(*) into v_members from public.gacha_s2_guild_members where guild_id = p_guild_id;
  if v_members = 0 then
    return jsonb_build_object('weekStart', v_week, 'memberCount', 0, 'goals', '[]'::jsonb, 'allComplete', false);
  end if;

  for v_goal in
    select * from (values
      ('adventure', '모험 클리어', 10),
      ('minigame', '미니게임 플레이', 7),
      ('worldboss', '월드보스 공격', 4)
    ) as g(key, label, per_member)
  loop
    -- 인원 비례: perMember × 인원 (기준 30명일 때 300 / 210 / 120)
    v_target := ceil(v_goal.per_member::numeric * v_members)::integer;
    v_cap := greatest(1, ceil(v_target * 0.08)::integer);

    -- 개인별로 상한을 적용한 뒤 합산한다.
    select coalesce(sum(least(per_user.actions, v_cap)), 0) into v_progress
    from (
      select c.user_id, sum(c.actions) as actions
      from public.gacha_s2_guild_contributions c
      where c.guild_id = p_guild_id
        and c.source = v_goal.key
        and c.day_kst >= v_week
        and c.day_kst < v_week + 7
      group by c.user_id
    ) per_user;

    if v_progress < v_target then v_all_complete := false; end if;
    v_goals := v_goals || jsonb_build_object(
      'key', v_goal.key,
      'label', v_goal.label,
      'target', v_target,
      'progress', least(v_progress, v_target),
      'memberCap', v_cap,
      'complete', v_progress >= v_target
    );
  end loop;

  return jsonb_build_object(
    'weekStart', v_week,
    'memberCount', v_members,
    'goals', v_goals,
    'allComplete', v_all_complete
  );
end;
$$;

-- 트리거 교체: GP 와 함께 수행 횟수(actions)도 적립한다.
-- 기존 게임 RPC 는 여전히 건드리지 않는다.
create or replace function public.gacha_s2_guild_gp_from_command()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_gp integer;
  v_source text;
  v_guild_id uuid;
  v_day date;
  v_today integer;
  v_cap constant integer := 200;
  v_award integer;
begin
  case new.command_type
    when 'finishAdventureRun' then v_gp := 5;  v_source := 'adventure';
    when 'finishMinigame'     then v_gp := 2;  v_source := 'minigame';
    when 'playLadder'         then v_gp := 2;  v_source := 'minigame';
    when 'attackWorldBoss'    then v_gp := 10; v_source := 'worldboss';
    when 'attackGuildRaid'    then v_gp := 15; v_source := 'raid';
    else return new;
  end case;

  select m.guild_id into v_guild_id
  from public.gacha_s2_guild_members m
  join public.gacha_s2_guilds g on g.guild_id = m.guild_id
  where m.user_id = new.user_id and g.disbanded_at is null;
  if v_guild_id is null then return new; end if;

  v_day := (now() at time zone 'Asia/Seoul')::date;

  -- GP 는 하루 개인 상한을 받지만, 주간 목표용 수행 횟수는 상한과 무관하게 센다.
  -- 상한 때문에 GP 가 0 이어도 목표 진행에는 기여해야 하기 때문이다.
  select coalesce(sum(gp), 0) into v_today
  from public.gacha_s2_guild_contributions
  where user_id = new.user_id and day_kst = v_day;
  v_award := greatest(0, least(v_gp, v_cap - v_today));

  insert into public.gacha_s2_guild_contributions (guild_id, user_id, day_kst, source, gp, actions)
  values (v_guild_id, new.user_id, v_day, v_source, v_award, 1)
  on conflict (guild_id, user_id, day_kst, source) do update
  set gp = public.gacha_s2_guild_contributions.gp + excluded.gp,
      actions = public.gacha_s2_guild_contributions.actions + 1,
      updated_at = now();

  if v_award > 0 then
    update public.gacha_s2_guild_members
    set weekly_gp = weekly_gp + v_award,
        total_gp = total_gp + v_award,
        last_contributed_at = now()
    where guild_id = v_guild_id and user_id = new.user_id;

    update public.gacha_s2_guilds
    set total_gp = total_gp + v_award
    where guild_id = v_guild_id;

    perform public.gacha_s2_guild_refresh_level(v_guild_id);
  else
    update public.gacha_s2_guild_members
    set last_contributed_at = now()
    where guild_id = v_guild_id and user_id = new.user_id;
  end if;

  return new;
end;
$$;

create or replace function public.gacha_s2_claim_guild_weekly_reward(
  p_user_id uuid,
  p_expected_revision bigint,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
  v_request_hash text;
  v_previous public.gacha_s2_idempotency%rowtype;
  v_guild_id uuid;
  v_week date := public.gacha_s2_guild_week_start();
  v_progress jsonb;
  v_points constant integer := 80000;
begin
  if p_user_id is null
    or p_expected_revision is null or p_expected_revision < 0
    or p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128 then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VALIDATION_FAILED', '주간 보상 요청이 올바르지 않습니다.',
      greatest(coalesce(p_expected_revision, 0), 0), null, null
    );
  end if;

  v_request_hash := encode(digest(jsonb_build_object(
    'type', 'claimGuildWeeklyReward', 'expectedRevision', p_expected_revision, 'week', v_week
  )::text, 'sha256'), 'hex');

  select revision into v_revision
  from public.gacha_s2_player_states where user_id = p_user_id for update;
  if not found then
    return public.gacha_s2_command_error(p_idempotency_key, 'AUTH_REQUIRED', '계정 상태를 찾을 수 없습니다.', 0, null, null);
  end if;

  select * into v_previous from public.gacha_s2_idempotency
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_previous.request_hash <> v_request_hash or v_previous.command_type <> 'claimGuildWeeklyReward' then
      return public.gacha_s2_command_error(
        p_idempotency_key, 'IDEMPOTENCY_KEY_REUSED', '같은 멱등 키를 다른 요청에 사용할 수 없습니다.',
        v_revision, null, null
      );
    end if;
    return v_previous.response;
  end if;

  if p_expected_revision <> v_revision then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'VERSION_CONFLICT', '최신 기록을 다시 불러와 주세요.',
      v_revision, public.gacha_s2_get_player_snapshot(p_user_id), null
    );
  end if;

  select gm.guild_id into v_guild_id from public.gacha_s2_guild_membership(p_user_id) gm;
  if v_guild_id is null then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '소속된 길드가 없습니다.', v_revision, null, null
    );
  end if;

  if exists (
    select 1 from public.gacha_s2_guild_weekly_claims
    where guild_id = v_guild_id and week_start_kst = v_week and user_id = p_user_id
  ) then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '이번 주 보상을 이미 받았습니다.', v_revision, null, null
    );
  end if;

  v_progress := public.gacha_s2_guild_weekly_progress(v_guild_id, v_week);
  if not (v_progress->>'allComplete')::boolean then
    return public.gacha_s2_command_error(
      p_idempotency_key, 'COMMAND_REJECTED', '주간 목표를 아직 달성하지 못했습니다.', v_revision, null, null
    );
  end if;

  insert into public.gacha_s2_guild_weekly_claims (guild_id, user_id, week_start_kst, points)
  values (v_guild_id, p_user_id, v_week, v_points);

  update public.gacha_s2_player_states
  set points = points + v_points
  where user_id = p_user_id;

  return public.gacha_s2_guild_command_ok(
    p_user_id, p_idempotency_key, 'claimGuildWeeklyReward', v_request_hash, v_revision,
    jsonb_build_object('guildId', v_guild_id, 'weekStart', v_week, 'points', v_points)
  );
end;
$$;

alter table public.gacha_s2_guild_weekly_claims enable row level security;
revoke all on table public.gacha_s2_guild_weekly_claims from public, anon, authenticated;
revoke all on function public.gacha_s2_guild_week_start(timestamptz) from public, anon, authenticated;
revoke all on function public.gacha_s2_guild_weekly_progress(uuid, date) from public, anon, authenticated;
revoke all on function public.gacha_s2_claim_guild_weekly_reward(uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.gacha_s2_guild_weekly_progress(uuid, date) to service_role;
grant execute on function public.gacha_s2_claim_guild_weekly_reward(uuid, bigint, text) to service_role;


-- 조회 RPC 갱신: 주간 공동목표 진행도를 함께 내려보낸다.
-- weekly_progress 함수가 이 파일에서 정의되므로 M1 조회 RPC 를 여기서 다시 만든다.
create or replace function public.gacha_s2_get_guild_state(p_user_id uuid, p_guild_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_guild_id uuid;
  v_role text;
  v_guild public.gacha_s2_guilds%rowtype;
  v_is_member boolean := false;
  v_can_manage boolean := false;
  v_penalty timestamptz;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;

  select gm.guild_id, gm.role into v_guild_id, v_role
  from public.gacha_s2_guild_membership(p_user_id) gm;

  -- 조회 대상: 인자로 받은 길드가 우선, 없으면 본인 소속 길드.
  if p_guild_id is not null then
    select * into v_guild from public.gacha_s2_guilds
    where guild_id = p_guild_id and disbanded_at is null;
  elsif v_guild_id is not null then
    select * into v_guild from public.gacha_s2_guilds where guild_id = v_guild_id;
  end if;

  select penalty_until into v_penalty
  from public.gacha_s2_guild_leave_penalties
  where user_id = p_user_id and penalty_until > now();

  if v_guild.guild_id is null then
    -- 소속도 없고 지정한 길드도 없으면 길드 목록만 돌려준다.
    return jsonb_build_object(
      'ok', true,
      'membership', null,
      'penaltyUntil', case when v_penalty is null then null
        else floor(extract(epoch from v_penalty) * 1000)::bigint end,
      'guild', null,
      'guilds', public.gacha_s2_list_guilds(),
      'emblems', public.gacha_s2_list_guild_emblems(),
      -- 길드는 방송인만 만들 수 있다. 클라가 생성 폼을 보일지 판단할 근거가 필요하다.
      'canCreateGuild', coalesce((select is_streamer from public.gacha_s2_accounts where id = p_user_id), false),
      'weekly', null
    );
  end if;

  v_is_member := v_guild_id is not null and v_guild_id = v_guild.guild_id;
  v_can_manage := v_is_member and v_role in ('owner', 'officer');

  return jsonb_build_object(
    'ok', true,
    'membership', case when v_guild_id is null then null else jsonb_build_object(
      'guildId', v_guild_id, 'role', v_role
    ) end,
    'penaltyUntil', case when v_penalty is null then null
      else floor(extract(epoch from v_penalty) * 1000)::bigint end,
    'guild', jsonb_build_object(
      'guildId', v_guild.guild_id,
      'name', v_guild.name,
      'tag', v_guild.tag,
      'notice', v_guild.notice,
      'emblem', v_guild.emblem,
      'joinMode', v_guild.join_mode,
      'level', v_guild.level,
      'totalGp', v_guild.total_gp,
      'memberLimit', v_guild.member_limit,
      'ownerUserId', v_guild.owner_user_id,
      'createdAt', floor(extract(epoch from v_guild.created_at) * 1000)::bigint,
      'memberCount', (
        select count(*) from public.gacha_s2_guild_members where guild_id = v_guild.guild_id
      )
    ),
    -- 멤버 목록: 기여도 판단 근거를 길드원 전원에게 공개한다.
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', m.user_id,
        'nickname', a.nickname,
        'role', m.role,
        'weeklyGp', m.weekly_gp,
        'totalGp', m.total_gp,
        'joinedAt', floor(extract(epoch from m.joined_at) * 1000)::bigint,
        'lastContributedAt', case when m.last_contributed_at is null then null
          else floor(extract(epoch from m.last_contributed_at) * 1000)::bigint end
      ) order by
        case m.role when 'owner' then 0 when 'officer' then 1 else 2 end,
        m.weekly_gp desc)
      from public.gacha_s2_guild_members m
      join public.gacha_s2_accounts a on a.id = m.user_id
      where m.guild_id = v_guild.guild_id
    ), '[]'::jsonb),
    -- 가입 신청 목록은 승인 권한자에게만 노출한다.
    'joinRequests', case when v_can_manage then coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', r.user_id,
        'nickname', a.nickname,
        'requestedAt', floor(extract(epoch from r.requested_at) * 1000)::bigint
      ) order by r.requested_at)
      from public.gacha_s2_guild_join_requests r
      join public.gacha_s2_accounts a on a.id = r.user_id
      where r.guild_id = v_guild.guild_id and r.status = 'pending'
    ), '[]'::jsonb) else null end,
    -- 본인이 보낸 대기 중 신청(다른 길드 포함).
    'myRequests', coalesce((
      select jsonb_agg(jsonb_build_object('guildId', r.guild_id, 'name', g.name))
      from public.gacha_s2_guild_join_requests r
      join public.gacha_s2_guilds g on g.guild_id = r.guild_id
      where r.user_id = p_user_id and r.status = 'pending' and g.disbanded_at is null
    ), '[]'::jsonb),
    'guilds', public.gacha_s2_list_guilds(),
    'emblems', public.gacha_s2_list_guild_emblems(),
    'canCreateGuild', coalesce((select is_streamer from public.gacha_s2_accounts where id = p_user_id), false),
    -- 주간 공동목표 진행도와 본인 수령 여부(PDB-16 3.2)
    'weekly', case when v_is_member then
      public.gacha_s2_guild_weekly_progress(v_guild.guild_id)
      || jsonb_build_object('claimed', exists (
           select 1 from public.gacha_s2_guild_weekly_claims
           where guild_id = v_guild.guild_id
             and week_start_kst = public.gacha_s2_guild_week_start()
             and user_id = p_user_id))
      else null end
  );
end;
$$;
