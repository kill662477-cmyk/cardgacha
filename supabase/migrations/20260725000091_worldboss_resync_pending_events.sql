-- 월드보스 config(maxHp / serverDamagePerSecond) 변경분을 "아직 시작하지 않은" 이벤트 행에 반영한다.
--
-- 배경: gacha_s2_ensure_world_boss_schedule 은 현재 슬롯과 다음 슬롯을
-- `on conflict (event_id) do nothing` 으로 미리 생성한다. 그리고
-- gacha_s2_sync_world_boss_event 는 config 를 다시 읽지 않고 행에 저장된
-- max_hp / server_damage_per_second 를 그대로 사용한다.
-- 따라서 config 를 바꿔도 "이미 선생성된 다음 슬롯" 행은 옛 값으로 남아,
-- 그 회차만 구 난이도로 진행되는 문제가 생긴다.
-- (실제로 서버DPS 폐지 직후 다음 회차가 구 값 65억 / DPS 3,596,667 로 남아 있었다.)
--
-- 안전장치: 아직 시작 전(starts_at > now)이고, 아무도 공격하지 않았고(player_damage = 0),
-- 처치되지 않은(defeated_at is null) 행만 갱신한다. 진행 중이거나 종료된 회차는 절대 건드리지 않는다.
-- max_hp 와 current_hp 를 같은 값으로 함께 갱신하므로 current_hp <= max_hp 체크 제약도 안전하다.
--
-- 앞으로 월드보스 HP/서버DPS config 를 바꿀 때는 이 마이그레이션과 동일한 UPDATE 를 함께 실행해야 한다.
with tier as (
  select
    e.event_id,
    (b.config->'worldBossRules'->'slotTiers'->(((right(e.event_id, 2))::integer)::text)->>'maxHp')::bigint as max_hp,
    (b.config->'worldBossRules'->'slotTiers'->(((right(e.event_id, 2))::integer)::text)->>'serverDamagePerSecond')::bigint as dps
  from public.gacha_s2_world_boss_events e
  cross join (select config from public.gacha_s2_balance_versions where active) b
  where e.starts_at > now()
    and e.player_damage = 0
    and e.defeated_at is null
)
update public.gacha_s2_world_boss_events e
set max_hp = tier.max_hp,
    current_hp = tier.max_hp,
    server_damage_per_second = tier.dps,
    updated_at = now()
from tier
where e.event_id = tier.event_id
  and tier.max_hp is not null
  and tier.dps is not null;

do $$
declare v_stale integer;
begin
  select count(*) into v_stale
  from public.gacha_s2_world_boss_events e
  cross join (select config from public.gacha_s2_balance_versions where active) b
  where e.starts_at > now()
    and e.player_damage = 0
    and e.defeated_at is null
    and (
      e.max_hp is distinct from
        (b.config->'worldBossRules'->'slotTiers'->(((right(e.event_id, 2))::integer)::text)->>'maxHp')::bigint
      or e.server_damage_per_second is distinct from
        (b.config->'worldBossRules'->'slotTiers'->(((right(e.event_id, 2))::integer)::text)->>'serverDamagePerSecond')::bigint
    );
  if v_stale > 0 then
    raise exception 'pending world boss events still stale: %', v_stale;
  end if;
end;
$$;
