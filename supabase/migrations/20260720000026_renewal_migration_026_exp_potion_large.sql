-- migration 026: update cardExpPotionLarge cardExp to 20

update public.gacha_s2_balance_versions
set config = jsonb_set(
  config,
  '{supportItems,cardExpPotionLarge}',
  config->'supportItems'->'cardExpPotionLarge' || '{"effect": "선택 카드 EXP +20", "cardExp": 20}'::jsonb
)
where active = true;
