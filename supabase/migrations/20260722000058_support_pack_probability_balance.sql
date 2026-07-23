-- Reduce action-energy items and raise destruction-guard odds in support packs.

begin;

insert into public.gacha_s2_balance_versions (
  version, config_hash, catalog_hash, config, active, activated_at
)
select
  '2026.07.22-support-pack-balance-1',
  '159e0b64b78370db335a62196d3ff478a64946923cb2277fe18a26394535aea8',
  catalog_hash,
  jsonb_set(
    jsonb_set(
      config,
      '{balanceVersion}',
      to_jsonb('2026.07.22-support-pack-balance-1'::text),
      true
    ),
    '{supportPack}',
    $support${
      "name":"작전 지원 보급팩",
      "price":150,
      "tenPrice":1500,
      "items":{
        "energySmall":14,
        "energyMedium":8,
        "energyLarge":2,
        "enhance5":16,
        "enhance10":6,
        "destructionGuard":5,
        "cardExpPotion":10,
        "exp30m":16,
        "exp2h":9,
        "generalTicket":7,
        "eliteTicket":3.5,
        "raceTicket":2,
        "premiumTicket":0.5,
        "adventureRunReset":0.25,
        "quickBattleReset":0.75
      },
      "rareItems":[
        "energyLarge",
        "enhance10",
        "destructionGuard",
        "exp2h",
        "generalTicket",
        "eliteTicket",
        "raceTicket",
        "premiumTicket",
        "adventureRunReset",
        "quickBattleReset"
      ],
      "guaranteeRates":{
        "energyLarge":7,
        "enhance10":24,
        "destructionGuard":6,
        "exp2h":28,
        "generalTicket":15,
        "eliteTicket":8,
        "raceTicket":5,
        "premiumTicket":2,
        "adventureRunReset":1,
        "quickBattleReset":4
      }
    }$support$::jsonb,
    true
  ),
  false,
  now()
from public.gacha_s2_balance_versions
where active
on conflict (version) do update
set config_hash = excluded.config_hash,
    catalog_hash = excluded.catalog_hash,
    config = excluded.config,
    activated_at = excluded.activated_at;

update public.gacha_s2_balance_versions set active = false where active;
update public.gacha_s2_balance_versions
set active = true, activated_at = now()
where version = '2026.07.22-support-pack-balance-1';

commit;
