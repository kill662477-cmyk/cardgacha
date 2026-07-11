-- card-gacha 4차 마이그레이션
-- Supabase 콘솔 > SQL Editor 에 붙여넣고 실행하세요.
-- 유저 테이블에 랭킹 점수 컬럼을 추가합니다.

alter table gacha_users add column if not exists ranking_score int not null default 0;
