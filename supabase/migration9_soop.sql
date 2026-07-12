-- card-gacha 9차 마이그레이션: SOOP(숲) OAuth 로그인
-- Supabase 콘솔 > SQL Editor 에 붙여넣고 실행하세요. (여러 번 실행해도 안전, idempotent)
--
-- SOOP 로그인 계정을 기존 gacha_users 에 통합한다.
-- SOOP OpenAPI 의 user/stationinfo 응답에는 고유 user_id 필드가 없으므로
-- station_name(방송국명=아이디 성격)을 계정 고유키(soop_id)로 사용한다.
-- user_nick(표시 닉네임)은 변경 가능하므로 로그인마다 nickname 컬럼을 갱신한다.
--
-- 수동 KEY 가입 계정은 soop_id 가 NULL 이다(Postgres 는 NULL 을 중복으로 보지 않으므로
-- unique 제약과 공존한다).

alter table public.gacha_users add column if not exists soop_id text;

create unique index if not exists gacha_users_soop_id_key
  on public.gacha_users(soop_id);
