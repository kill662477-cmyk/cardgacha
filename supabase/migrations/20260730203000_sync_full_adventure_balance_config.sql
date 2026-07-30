-- 이미 적용된 밸런스 버전의 regions/stages가 과거 5개 지역·50스테이지에 머문 상태를 복구한다.
-- 현재 소스와 같은 11개 지역·110스테이지를 DB 활성 밸런스에도 생성하고,
-- NULL을 통과시키지 않는 검증으로 Hell10 수치를 확정한다.
begin;

do $sync_adventure_balance$
declare
  v_config jsonb;
  v_regions jsonb;
  v_stages jsonb;
  v_hash text;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active;

  if v_config is null then
    raise exception 'active balance config missing';
  end if;

  v_regions := $regions$[
    {"id":1,"name":"끊어진 전파도시","code":"signal-city","hpBase":590000,"attackBase":3000,"bossHp":1200000,"bossAttack":4000},
    {"id":2,"name":"침묵한 중계기지","code":"relay-base","hpBase":1100000,"attackBase":4500,"bossHp":1820000,"bossAttack":6000},
    {"id":3,"name":"검게 물든 스튜디오","code":"black-studio","hpBase":1700000,"attackBase":6500,"bossHp":2800000,"bossAttack":8500},
    {"id":4,"name":"폭주한 데이터 요새","code":"data-fortress","hpBase":2500000,"attackBase":9000,"bossHp":4000000,"bossAttack":11000},
    {"id":5,"name":"악플 코어 심층부","code":"malice-core","hpBase":4200000,"attackBase":12500,"bossHp":7500000,"bossAttack":16000},
    {"id":6,"name":"붕괴한 신호 폐허","code":"void-rift","mode":"hard","hpBase":8862500,"attackBase":26393,"bossHp":11812500,"bossAttack":24438,"duration":46,"bossDuration":56},
    {"id":7,"name":"심연의 중계 감옥","code":"abyss-relay","mode":"hard","hpBase":10803200,"attackBase":30281,"bossHp":14259200,"bossAttack":28156,"duration":48,"bossDuration":58},
    {"id":8,"name":"악몽 송출 스튜디오","code":"nightmare-studio","mode":"hard","hpBase":12922800,"attackBase":36975,"bossHp":17820000,"bossAttack":34510,"duration":50,"bossDuration":60},
    {"id":9,"name":"오메가 데이터 성채","code":"omega-fortress","mode":"hard","hpBase":15150400,"attackBase":44880,"bossHp":22032000,"bossAttack":41374,"duration":52,"bossDuration":62},
    {"id":10,"name":"지옥 악플 코어","code":"hell-core","mode":"hard","hpBase":17985600,"attackBase":48960,"bossHp":27216000,"bossAttack":48195,"duration":59,"bossDuration":64},
    {"id":11,"name":"최후 심판 성역","code":"hell-final","mode":"hell","hpBase":24000000,"attackBase":52000,"bossHp":48000000,"bossAttack":50000,"duration":66,"bossDuration":78}
  ]$regions$::jsonb;

  select jsonb_agg(
    jsonb_build_object(
      'id', format('%s-%s', region->>'id', stage_number),
      'displayName', case
        when region->>'mode' = 'hell' then format('Hell%s', stage_number)
        else format('%s-%s', region->>'id', stage_number)
      end,
      'region', region->>'name',
      'regionCode', region->>'code',
      'regionIndex', (region_order - 1)::integer,
      'stageNumber', stage_number,
      'globalNumber', ((region_order - 1) * 10 + stage_number)::integer,
      'mode', coalesce(region->>'mode', 'normal'),
      'hard', coalesce(region->>'mode', '') = 'hard',
      'hell', coalesce(region->>'mode', '') = 'hell',
      'enemyType', case
        when stage_number = 10 then 'boss'
        else (array['crawler', 'jammer', 'leech', 'crusher'])[
          mod((stage_number - 1) + (region_order - 1)::integer, 4) + 1
        ]
      end,
      'enemyCount', case
        when stage_number = 10 then 1
        else least(7, 4 + floor(stage_number / 3.0)::integer)
      end,
      'enemyHp', case
        when stage_number = 10 then (region->>'bossHp')::bigint
        else round(
          (region->>'hpBase')::numeric
          * power(
            case
              when region->>'mode' = 'hell' then 1.008
              when region->>'mode' = 'hard' then 1.018
              when (region->>'id')::integer = 1 then 1.08
              else 1.025
            end,
            stage_number - 1
          )
        )::bigint
      end,
      'enemyAttack', case
        when stage_number = 10 then (region->>'bossAttack')::bigint
        else round(
          (region->>'attackBase')::numeric
          * power(
            case
              when region->>'mode' = 'hell' then 1.01
              when region->>'mode' = 'hard' then 1.012
              when (region->>'id')::integer = 1 then 1.03
              else 1.02
            end,
            stage_number - 1
          )
        )::bigint
      end,
      'duration', case
        when region->>'mode' in ('hard', 'hell') then
          case when stage_number = 10
            then (region->>'bossDuration')::integer
            else (region->>'duration')::integer
          end
        when stage_number = 10 then 40 + (region_order - 1)::integer * 3
        else 30 + (region_order - 1)::integer * 2
          + case when (region->>'id')::integer = 1 then stage_number - 1 else 0 end
      end,
      'rewardPoints', 18 + ((region_order - 1) * 10 + stage_number)::integer * 4,
      'boss', stage_number = 10
    )
    order by region_order, stage_number
  )
  into v_stages
  from jsonb_array_elements(v_regions) with ordinality as regions(region, region_order)
  cross join generate_series(1, 10) as stages(stage_number);

  v_config := jsonb_set(v_config, '{balanceVersion}', '"2026.07.30-hell10-worldboss-retune-2"'::jsonb, true);
  v_config := jsonb_set(v_config, '{regions}', v_regions, true);
  v_config := jsonb_set(v_config, '{stages}', v_stages, true);
  v_hash := encode(digest(v_config::text, 'sha256'), 'hex');

  insert into public.gacha_s2_balance_versions (
    version, config, config_hash, catalog_hash, active
  )
  select
    '2026.07.30-hell10-worldboss-retune-2',
    v_config,
    v_hash,
    catalog_hash,
    false
  from public.gacha_s2_balance_versions
  where active
  on conflict (version) do update
  set config = excluded.config,
      config_hash = excluded.config_hash,
      catalog_hash = excluded.catalog_hash,
      active = false;

  update public.gacha_s2_balance_versions
  set active = (version = '2026.07.30-hell10-worldboss-retune-2');
end;
$sync_adventure_balance$;

do $verify$
declare
  v_config jsonb;
begin
  select config into v_config
  from public.gacha_s2_balance_versions
  where active and version = '2026.07.30-hell10-worldboss-retune-2';

  if v_config is null then
    raise exception 'synced balance version activation failed';
  end if;
  if jsonb_array_length(v_config->'regions') is distinct from 11
    or jsonb_array_length(v_config->'stages') is distinct from 110 then
    raise exception 'adventure balance catalog length mismatch';
  end if;
  if v_config->'stages'->109->>'id' is distinct from '11-10'
    or (v_config->'regions'->10->>'bossHp')::bigint is distinct from 48000000
    or (v_config->'regions'->10->>'bossAttack')::bigint is distinct from 50000
    or (v_config->'stages'->109->>'enemyHp')::bigint is distinct from 48000000
    or (v_config->'stages'->109->>'enemyAttack')::bigint is distinct from 50000
    or (v_config->'stages'->109->>'duration')::integer is distinct from 78 then
    raise exception 'Hell10 balance sync failed';
  end if;
end;
$verify$;

commit;
