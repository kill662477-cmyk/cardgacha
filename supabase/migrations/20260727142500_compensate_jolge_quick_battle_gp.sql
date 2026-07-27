-- 2026-07-27 17:11 KST에 빠른전투를 3회 완료했지만 GP 트리거 누락으로
-- 반영되지 않은 '졸게' 계정 한 명만 보정한다.
create table if not exists public.gacha_s2_guild_gp_adjustments (
  adjustment_key text primary key,
  user_id uuid not null references public.gacha_s2_accounts(id) on delete restrict,
  guild_id uuid not null references public.gacha_s2_guilds(guild_id) on delete restrict,
  nickname text not null,
  source text not null,
  gp_granted integer not null check (gp_granted >= 0),
  actions_granted integer not null check (actions_granted > 0),
  created_at timestamptz not null default now()
);

alter table public.gacha_s2_guild_gp_adjustments enable row level security;

revoke all on table public.gacha_s2_guild_gp_adjustments
from public, anon, authenticated;

do $$
declare
  v_adjustment_key constant text := 'jolge-quick-battle-gp-20260727-1711';
  v_user_id uuid;
  v_guild_id uuid;
  v_account_count integer;
  v_quick_count integer;
  v_today_gp integer;
  v_award integer;
  v_inserted text;
begin
  select count(*)
  into v_account_count
  from public.gacha_s2_accounts
  where btrim(nickname) = '졸게';

  if v_account_count <> 1 then
    raise exception 'Jolge compensation target count mismatch: %', v_account_count;
  end if;

  select id
  into v_user_id
  from public.gacha_s2_accounts
  where btrim(nickname) = '졸게';

  select guild_id
  into v_guild_id
  from public.gacha_s2_guild_members
  where user_id = v_user_id;

  if v_guild_id is null then
    raise exception 'Jolge compensation target is not a guild member';
  end if;

  select count(*)
  into v_quick_count
  from public.gacha_s2_command_audit
  where user_id = v_user_id
    and command_type = 'claimQuickBattle'
    and created_at >= timestamptz '2026-07-27 08:11:00+00'
    and created_at < timestamptz '2026-07-27 08:12:00+00';

  if v_quick_count <> 3 then
    raise exception 'Jolge quick-battle evidence count mismatch: %', v_quick_count;
  end if;

  select coalesce(sum(gp), 0)
  into v_today_gp
  from public.gacha_s2_guild_contributions
  where user_id = v_user_id
    and day_kst = date '2026-07-27';

  v_award := greatest(0, least(15, 200 - v_today_gp));

  insert into public.gacha_s2_guild_gp_adjustments (
    adjustment_key, user_id, guild_id, nickname, source, gp_granted, actions_granted
  ) values (
    v_adjustment_key, v_user_id, v_guild_id, '졸게', 'adventure', v_award, 3
  )
  on conflict (adjustment_key) do nothing
  returning adjustment_key into v_inserted;

  if v_inserted is null then
    return;
  end if;

  insert into public.gacha_s2_guild_contributions (
    guild_id, user_id, day_kst, source, gp, actions
  ) values (
    v_guild_id, v_user_id, date '2026-07-27', 'adventure', v_award, 3
  )
  on conflict (guild_id, user_id, day_kst, source) do update
  set gp = public.gacha_s2_guild_contributions.gp + excluded.gp,
      actions = public.gacha_s2_guild_contributions.actions + excluded.actions,
      updated_at = now();

  update public.gacha_s2_guild_members
  set weekly_gp = weekly_gp + v_award,
      total_gp = total_gp + v_award,
      last_contributed_at = now()
  where guild_id = v_guild_id and user_id = v_user_id;

  update public.gacha_s2_guilds
  set total_gp = total_gp + v_award
  where guild_id = v_guild_id;

  perform public.gacha_s2_guild_refresh_level(v_guild_id);
end;
$$;
