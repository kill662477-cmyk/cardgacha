-- card-gacha 5차 마이그레이션
-- Supabase 콘솔 > SQL Editor 에 붙여넣고 실행하세요.
-- 유저의 접속 IP를 기록하기 위한 컬럼입니다.

alter table gacha_users add column if not exists last_ip text;
