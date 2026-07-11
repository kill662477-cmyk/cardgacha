-- card-gacha 3차 마이그레이션
-- Supabase 콘솔 > SQL Editor 에 붙여넣고 실행하세요.
-- 여러 번 실행해도 안전합니다(idempotent).
-- 기존 유저 데이터는 건드리지 않습니다.

-- 1. 신규 가입자 초기 포인트: 1000 → 2000
alter table gacha_users alter column points set default 2000;
