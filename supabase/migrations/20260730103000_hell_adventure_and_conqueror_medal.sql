-- Final adventure: Hell1~Hell10 and the permanent Hell10 conqueror medal.
-- The medal is derived from the authoritative cleared_stage (>= 110), so it cannot
-- be duplicated, consumed, or desynchronized from ranking/profile displays.
begin;

do $$
declare
  v_config jsonb;
  v_hash text;
begin
  select config into v_config from public.gacha_s2_balance_versions where active;
  if v_config is null then raise exception 'active balance config missing'; end if;

  v_config := jsonb_set(v_config, '{balanceVersion}', '"2026.07.30-hell-adventure-1"'::jsonb, true);
  v_config := jsonb_set(v_config, '{rewardRules,maxStage}', '110'::jsonb, true);
  v_config := jsonb_set(v_config, '{adventureRules,modes}', '{
    "normal":{"label":"일반 모험","startStage":1,"endStage":50,"stageCount":50,"unlockStage":0},
    "hard":{"label":"하드 모험","startStage":51,"endStage":100,"stageCount":50,"unlockStage":50},
    "hell":{"label":"HELL","startStage":101,"endStage":110,"stageCount":10,"unlockStage":100}
  }'::jsonb, true);
  v_config := jsonb_set(v_config, '{adventureRules,hellRunReward}', '{
    "minPointsPerRun":12000,"maxPointsPerRun":25000,"cardExpPerClearedStage":2
  }'::jsonb, true);
  v_hash := encode(digest(v_config::text, 'sha256'), 'hex');

  insert into public.gacha_s2_balance_versions(version, config, config_hash, catalog_hash, active)
  select '2026.07.30-hell-adventure-1', v_config, v_hash, catalog_hash, false
  from public.gacha_s2_balance_versions where active
  on conflict (version) do update
    set config = excluded.config,
        config_hash = excluded.config_hash,
        catalog_hash = excluded.catalog_hash,
        active = false;

  update public.gacha_s2_balance_versions
  set active = (version = '2026.07.30-hell-adventure-1');
end;
$$;

do $$
declare
  v_constraint record;
begin
  for v_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public.gacha_s2_player_states'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%cleared_stage%'
  loop
    execute format('alter table public.gacha_s2_player_states drop constraint %I', v_constraint.conname);
  end loop;
end;
$$;

alter table public.gacha_s2_player_states
  add constraint gacha_s2_player_states_cleared_stage_hell_check
  check (cleared_stage between 0 and 110);

alter table public.gacha_s2_adventure_runs
  drop constraint if exists gacha_s2_adventure_runs_mode_check;
alter table public.gacha_s2_adventure_runs
  add constraint gacha_s2_adventure_runs_mode_check
  check (mode in ('normal','hard','hell','quick','quick-hard'));

alter table public.gacha_s2_adventure_runs
  drop constraint if exists gacha_s2_adventure_runs_reward_points_check;
alter table public.gacha_s2_adventure_runs
  add constraint gacha_s2_adventure_runs_reward_points_check
  check (reward_points between 0 and 25000);

create or replace function public.gacha_s2_adventure_reward_points(
  p_config jsonb,
  p_mode text,
  p_cleared_stages integer
) returns integer
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v_stage_count integer := case when p_mode = 'hell' then 10 else 50 end;
  v_cleared integer := greatest(0, least(v_stage_count, coalesce(p_cleared_stages, 0)));
  v_reward jsonb;
begin
  if p_mode in ('hard', 'hell') then
    if v_cleared = 0 then return 0; end if;
    v_reward := case when p_mode = 'hell'
      then p_config->'adventureRules'->'hellRunReward'
      else p_config->'adventureRules'->'hardRunReward'
    end;
    return (v_reward->>'minPointsPerRun')::integer
      + ((v_reward->>'maxPointsPerRun')::integer - (v_reward->>'minPointsPerRun')::integer)
        * (v_cleared - 1) / greatest(1, v_stage_count - 1);
  end if;
  v_reward := p_config->'adventureRules'->'runReward';
  return least(
    (v_reward->>'maxPointsPerRun')::integer,
    floor(
      v_cleared * (v_reward->>'pointsBasePerStage')::numeric
      + (v_reward->>'pointsGrowthPerStage')::numeric * v_cleared * (v_cleared + 1) / 2
    )::integer
  );
end;
$$;

-- Patch the current trusted RPC definitions in place. Every expected source fragment
-- is asserted before EXECUTE so a drifted production function aborts the migration.
do $hell_patch$
declare
  v_def text;
  v_next text;
begin
  select pg_get_functiondef(
    'public.gacha_s2_finish_adventure_run(uuid,bigint,text,uuid)'::regprocedure
  ) into v_def;
  v_next := replace(v_def,
    'v_run.mode not in (''normal'',''hard'')',
    'v_run.mode not in (''normal'',''hard'',''hell'')');
  v_next := replace(v_next,
    'case when v_run.mode = ''hard''
      then v_config->''adventureRules''->''hardRunReward''
      else v_config->''adventureRules''->''runReward''
    end',
    'case when v_run.mode = ''hell''
      then v_config->''adventureRules''->''hellRunReward''
      when v_run.mode = ''hard'' then v_config->''adventureRules''->''hardRunReward''
      else v_config->''adventureRules''->''runReward''
    end');
  v_next := replace(v_next,
    'when v_run.mode = ''hard'' then 50 + v_run.verified_cleared_stages
    else v_run.verified_cleared_stages',
    'when v_run.mode = ''hell'' then 100 + v_run.verified_cleared_stages
    when v_run.mode = ''hard'' then 50 + v_run.verified_cleared_stages
    else v_run.verified_cleared_stages');
  v_next := replace(v_next,
    'status = case when verified_cleared_stages = 50 then ''completed'' else ''failed'' end',
    'status = case when verified_cleared_stages = case when v_run.mode = ''hell'' then 10 else 50 end then ''completed'' else ''failed'' end');
  v_next := replace(v_next,
    '''bonusItemId'', v_bonus_item, ''exAwards'', v_ex_result->''awards''',
    '''bonusItemId'', v_bonus_item, ''exAwards'', v_ex_result->''awards'',
      ''hellMedalAwarded'', v_cleared_stage < 110 and v_highest >= 110');
  if v_next = v_def
    or strpos(v_next, 'v_run.mode not in (''normal'',''hard'',''hell'')') = 0
    or strpos(v_next, 'v_config->''adventureRules''->''hellRunReward''') = 0
    or strpos(v_next, 'when v_run.mode = ''hell'' then 100 + v_run.verified_cleared_stages') = 0
    or strpos(v_next, 'verified_cleared_stages = case when v_run.mode = ''hell'' then 10 else 50 end') = 0
    or strpos(v_next, '''hellMedalAwarded''') = 0 then
    raise exception 'Hell finish-adventure patch source mismatch';
  end if;
  execute v_next;

  select pg_get_functiondef(
    'public.gacha_s2_start_adventure_run(uuid,bigint,text,integer,text,text)'::regprocedure
  ) into v_def;
  v_next := replace(v_def,
    'p_verified_cleared_stages not between 0 and 50',
    '(p_verified_cleared_stages < 0 or p_verified_cleared_stages > case when p_mode = ''hell'' then 10 else 50 end)');
  v_next := replace(v_next,
    'p_mode not in (''normal'',''hard'')',
    'p_mode not in (''normal'',''hard'',''hell'')');
  v_next := replace(v_next,
    'if p_mode = ''hard'' and v_cleared_stage < 50 then',
    'if p_mode = ''hell'' and v_cleared_stage < 100 then
    return public.gacha_s2_command_error(p_idempotency_key, ''COMMAND_REJECTED'', ''HELL은 하드 모험 10-10 클리어 후 해금됩니다.'', v_revision, null, null);
  end if;
  if p_mode = ''hard'' and v_cleared_stage < 50 then');
  v_next := replace(v_next,
    'v_start_stage := case when p_mode = ''hard'' then 51 else 1 end;',
    'v_start_stage := case when p_mode = ''hell'' then 101 when p_mode = ''hard'' then 51 else 1 end;');
  if v_next = v_def
    or strpos(v_next, 'p_verified_cleared_stages > case when p_mode = ''hell'' then 10 else 50 end') = 0
    or strpos(v_next, 'p_mode not in (''normal'',''hard'',''hell'')') = 0
    or strpos(v_next, 'p_mode = ''hell'' and v_cleared_stage < 100') = 0
    or strpos(v_next, 'when p_mode = ''hell'' then 101') = 0 then
    raise exception 'Hell start-adventure patch source mismatch';
  end if;
  execute v_next;

end;
$hell_patch$;

create or replace function public.gacha_s2_get_power_ranking(
  p_user_id uuid,
  p_verified_power integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rank integer;
  v_population integer;
  v_top_fifty_power integer := 0;
  v_leaders jsonb := '[]'::jsonb;
  v_nickname text;
  v_guild jsonb;
  v_hell_conqueror boolean := false;
begin
  if p_user_id is null or p_verified_power is null or p_verified_power < 0 or p_verified_power > 2000000000 then
    raise exception 'invalid power ranking input';
  end if;

  update public.gacha_s2_player_states
  set power_snapshot = p_verified_power, power_snapshot_at = now()
  where user_id = p_user_id;
  if not found then raise exception 'Season 2 account state not found'; end if;

  select account.nickname, state.cleared_stage >= 110
  into v_nickname, v_hell_conqueror
  from public.gacha_s2_accounts account
  join public.gacha_s2_player_states state on state.user_id = account.id
  where account.id = p_user_id;

  select case when g.guild_id is null then null else jsonb_build_object(
    'name', g.name, 'tag', g.tag, 'emblem', g.emblem, 'level', g.level
  ) end into v_guild
  from public.gacha_s2_guild_members m
  join public.gacha_s2_guilds g on g.guild_id = m.guild_id and g.disbanded_at is null
  where m.user_id = p_user_id;

  with ranked as (
    select state.user_id, account.nickname, state.power_snapshot, state.power_snapshot_at,
      state.cleared_stage >= 110 as hell_conqueror,
      coalesce(state.representative_card_id, state.formation[1]) as representative_card_id,
      state.formation,
      guild.name as guild_name, guild.tag as guild_tag,
      guild.emblem as guild_emblem, guild.level as guild_level,
      row_number() over (
        order by state.power_snapshot desc, state.power_snapshot_at asc nulls last, state.user_id
      )::integer as rank
    from public.gacha_s2_player_states state
    join public.gacha_s2_accounts account on account.id = state.user_id
    left join public.gacha_s2_guild_members member on member.user_id = state.user_id
    left join public.gacha_s2_guilds guild
      on guild.guild_id = member.guild_id and guild.disbanded_at is null
  )
  select
    (select count(*)::integer from ranked),
    (select rank from ranked where user_id = p_user_id),
    coalesce((select power_snapshot from ranked where rank = 50), 0),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', ranked.rank,
        'nickname', ranked.nickname,
        'power', ranked.power_snapshot,
        'hellConqueror', ranked.hell_conqueror,
        'representativeCardId', ranked.representative_card_id,
        'guild', case when ranked.guild_name is null then null else jsonb_build_object(
          'name', ranked.guild_name, 'tag', ranked.guild_tag,
          'emblem', ranked.guild_emblem, 'level', ranked.guild_level
        ) end,
        'formation', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'cardId', slot.card_id, 'enhancement', coalesce(pc.enhancement, 0)
          ) order by slot.ord), '[]'::jsonb)
          from unnest(coalesce(ranked.formation, '{}'::text[])) with ordinality as slot(card_id, ord)
          left join public.gacha_s2_player_cards pc
            on pc.user_id = ranked.user_id and pc.card_id = slot.card_id
        ),
        'mine', ranked.user_id = p_user_id
      ) order by ranked.rank)
      from ranked where ranked.rank <= 50
    ), '[]'::jsonb)
  into v_population, v_rank, v_top_fifty_power, v_leaders;

  return jsonb_build_object(
    'seasonId', 'season-2',
    'snapshotAt', public.gacha_s2_now_ms(),
    'population', v_population,
    'leaders', v_leaders,
    'topFiftyPower', v_top_fifty_power,
    'powerToTopFifty', case
      when v_rank <= 50 or v_top_fifty_power = 0 then 0
      else greatest(0, v_top_fifty_power - p_verified_power + 1)
    end,
    'player', jsonb_build_object(
      'nickname', v_nickname,
      'power', p_verified_power,
      'rank', v_rank,
      'guild', v_guild,
      'hellConqueror', v_hell_conqueror,
      'topPercent', case when v_population = 0 then 100 else round(v_rank::numeric * 100 / v_population, 1) end
    )
  );
end;
$$;

revoke all on function public.gacha_s2_adventure_reward_points(jsonb, text, integer) from public, anon, authenticated;
revoke all on function public.gacha_s2_start_adventure_run(uuid, bigint, text, integer, text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_finish_adventure_run(uuid, bigint, text, uuid) from public, anon, authenticated;
revoke all on function public.gacha_s2_claim_quick_battle(uuid, bigint, text, integer, text, text) from public, anon, authenticated;
revoke all on function public.gacha_s2_get_power_ranking(uuid, integer) from public, anon, authenticated;
grant execute on function public.gacha_s2_start_adventure_run(uuid, bigint, text, integer, text, text) to service_role;
grant execute on function public.gacha_s2_finish_adventure_run(uuid, bigint, text, uuid) to service_role;
grant execute on function public.gacha_s2_claim_quick_battle(uuid, bigint, text, integer, text, text) to service_role;
grant execute on function public.gacha_s2_get_power_ranking(uuid, integer) to service_role;

do $$
declare
  v_active text;
  v_config jsonb;
begin
  select version, config into v_active, v_config
  from public.gacha_s2_balance_versions where active;
  if v_active <> '2026.07.30-hell-adventure-1' then
    raise exception 'Hell adventure balance activation failed: %', coalesce(v_active, 'none');
  end if;
  if public.gacha_s2_adventure_reward_points(v_config, 'hell', 1) <> 12000
    or public.gacha_s2_adventure_reward_points(v_config, 'hell', 10) <> 25000 then
    raise exception 'Hell adventure reward validation failed';
  end if;
end;
$$;

commit;
