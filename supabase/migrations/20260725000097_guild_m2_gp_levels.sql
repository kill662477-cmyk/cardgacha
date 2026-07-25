-- 길드 M2: 공헌도(GP) 적립 · 길드 레벨 · 정원 확장 (PDB-16 3.1)
--
-- 설계 핵심: 기존 게임 RPC(모험·미니게임·월드보스)를 일절 수정하지 않는다.
-- 대신 모든 명령이 남기는 gacha_s2_command_audit 삽입을 트리거로 잡아 GP 를 적립한다.
-- 검증된 명령 경로에 손을 대지 않으므로 회귀 위험이 없고, 명령이 롤백되면 같은
-- 트랜잭션이라 GP 적립도 함께 롤백된다.
--
-- 그래서 GP 는 "스테이지 몇 개"가 아니라 명령 1회 단위로 센다. 감사 로그에는
-- 명령 종류만 남고 세부 결과가 없기 때문이다.

create table if not exists public.gacha_s2_guild_levels (
  level integer primary key check (level between 1 and 30),
  required_gp bigint not null check (required_gp >= 0),
  member_limit integer not null check (member_limit between 1 and 50),
  atk_bonus numeric(5,4) not null default 0 check (atk_bonus >= 0 and atk_bonus <= 0.5),
  hp_bonus numeric(5,4) not null default 0 check (hp_bonus >= 0 and hp_bonus <= 0.5),
  def_bonus numeric(5,4) not null default 0 check (def_bonus >= 0 and def_bonus <= 0.5),
  point_bonus numeric(5,4) not null default 0 check (point_bonus >= 0 and point_bonus <= 0.5)
);

insert into public.gacha_s2_guild_levels (level, required_gp, member_limit, atk_bonus, hp_bonus, def_bonus, point_bonus) values
  (1,      0, 30, 0.00, 0.00, 0.00, 0.00),
  (2,   3000, 40, 0.02, 0.00, 0.00, 0.00),
  (3,   8000, 50, 0.02, 0.02, 0.00, 0.00),
  (4,  15000, 50, 0.03, 0.02, 0.02, 0.00),
  (5,  25000, 50, 0.03, 0.03, 0.03, 0.00),
  (6,  36000, 50, 0.04, 0.03, 0.03, 0.00),
  (7,  50000, 50, 0.04, 0.04, 0.03, 0.03),
  (8,  70000, 50, 0.04, 0.04, 0.04, 0.03),
  (9,  92000, 50, 0.05, 0.04, 0.04, 0.04),
  (10,120000, 50, 0.05, 0.05, 0.04, 0.05)
on conflict (level) do update set
  required_gp = excluded.required_gp, member_limit = excluded.member_limit,
  atk_bonus = excluded.atk_bonus, hp_bonus = excluded.hp_bonus,
  def_bonus = excluded.def_bonus, point_bonus = excluded.point_bonus;

-- 일별·출처별 적립 내역. 하루 개인 상한 판정 근거이자 기여도 표시 자료다.
create table if not exists public.gacha_s2_guild_contributions (
  guild_id uuid not null references public.gacha_s2_guilds(guild_id) on delete cascade,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete cascade,
  day_kst date not null,
  source text not null check (source in ('adventure', 'minigame', 'worldboss', 'raid', 'donation')),
  gp integer not null default 0 check (gp >= 0),
  updated_at timestamptz not null default now(),
  primary key (guild_id, user_id, day_kst, source)
);
create index if not exists gacha_s2_guild_contributions_user_day_idx
  on public.gacha_s2_guild_contributions (user_id, day_kst);

-- 누적 GP 로 길드 레벨과 정원을 다시 계산한다.
create or replace function public.gacha_s2_guild_refresh_level(p_guild_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_total bigint;
  v_level integer;
  v_limit integer;
  v_members integer;
begin
  select total_gp into v_total from public.gacha_s2_guilds where guild_id = p_guild_id;
  if v_total is null then return; end if;

  select level, member_limit into v_level, v_limit
  from public.gacha_s2_guild_levels
  where required_gp <= v_total
  order by level desc
  limit 1;

  -- 정원은 줄이지 않는다. 이미 들어와 있는 길드원이 정원 초과 상태가 되면 안 된다.
  select count(*) into v_members from public.gacha_s2_guild_members where guild_id = p_guild_id;
  update public.gacha_s2_guilds
  set level = coalesce(v_level, 1),
      member_limit = greatest(coalesce(v_limit, 30), member_limit, v_members),
      updated_at = now()
  where guild_id = p_guild_id;
end;
$$;

-- 감사 로그 → GP 적립. 기존 명령 RPC 는 건드리지 않는다.
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

  -- 하루 개인 상한. 소수 인원이 혼자 레벨을 끌어올리지 못하게 한다.
  select coalesce(sum(gp), 0) into v_today
  from public.gacha_s2_guild_contributions
  where user_id = new.user_id and day_kst = v_day;
  if v_today >= v_cap then return new; end if;
  v_gp := least(v_gp, v_cap - v_today);

  insert into public.gacha_s2_guild_contributions (guild_id, user_id, day_kst, source, gp)
  values (v_guild_id, new.user_id, v_day, v_source, v_gp)
  on conflict (guild_id, user_id, day_kst, source) do update
  set gp = public.gacha_s2_guild_contributions.gp + excluded.gp, updated_at = now();

  update public.gacha_s2_guild_members
  set weekly_gp = weekly_gp + v_gp,
      total_gp = total_gp + v_gp,
      last_contributed_at = now()
  where guild_id = v_guild_id and user_id = new.user_id;

  update public.gacha_s2_guilds
  set total_gp = total_gp + v_gp
  where guild_id = v_guild_id;

  perform public.gacha_s2_guild_refresh_level(v_guild_id);
  return new;
end;
$$;

drop trigger if exists gacha_s2_guild_gp_trigger on public.gacha_s2_command_audit;
create trigger gacha_s2_guild_gp_trigger
after insert on public.gacha_s2_command_audit
for each row execute function public.gacha_s2_guild_gp_from_command();

-- 길드 버프 조회. 소속이 없으면 전부 0 이라 무소속 유저는 계산이 그대로다.
create or replace function public.gacha_s2_guild_buff(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select jsonb_build_object(
      'guildId', g.guild_id,
      'level', g.level,
      'atk', l.atk_bonus::float8,
      'hp', l.hp_bonus::float8,
      'def', l.def_bonus::float8,
      'points', l.point_bonus::float8
    )
    from public.gacha_s2_guild_members m
    join public.gacha_s2_guilds g on g.guild_id = m.guild_id and g.disbanded_at is null
    join public.gacha_s2_guild_levels l on l.level = g.level
    where m.user_id = p_user_id
  ), jsonb_build_object('guildId', null, 'level', 0, 'atk', 0, 'hp', 0, 'def', 0, 'points', 0));
$$;

alter table public.gacha_s2_guild_levels enable row level security;
alter table public.gacha_s2_guild_contributions enable row level security;
revoke all on table public.gacha_s2_guild_levels from public, anon, authenticated;
revoke all on table public.gacha_s2_guild_contributions from public, anon, authenticated;
revoke all on function public.gacha_s2_guild_refresh_level(uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_guild_gp_from_command() from public, anon, authenticated;
revoke all on function public.gacha_s2_guild_buff(uuid) from public, anon, authenticated;
grant execute on function public.gacha_s2_guild_buff(uuid) to service_role;
