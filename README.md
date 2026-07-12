# Calm MonstarZ 카드뽑기 (Gacha)

캄몬스타즈 크루 카드 수집 가챠 웹앱. 정적 프론트(`index.html`) + Vercel 서버리스(`api/`) + Supabase.

## 구조

```
card-gacha/
├─ index.html              프론트 SPA (로그인/상점/개봉연출/도감/합성/랭킹/후원브릿지 진입)
├─ donation-bridge.html    방송인용 SOOP 별풍선 후원 브리지 페이지(별도)
├─ api/                    Vercel 서버리스 함수 (CommonJS, service_role 키로 RLS 우회)
│   ├─ auth/               SOOP OAuth (메인 로그인)
│   │   ├─ soop-start.js         GET  숲 OAuth 시작 → SOOP 인증 페이지로 리다이렉트
│   │   └─ soop-callback.js      GET  콜백 → code 교환 → 계정 생성/갱신 → #soop=KEY
│   ├─ bridge/             방송인 후원 브리지 (별도 OAuth 스코프)
│   │   ├─ soop-start.js / soop-callback.js   브리지 전용 SOOP 연결
│   │   ├─ auth.js               POST  브리지 키로 세션 발급
│   │   ├─ credentials.js        GET   SOOP 클라이언트 정보
│   │   ├─ donation.js           POST  별풍선 후원 이벤트 → 양쪽에 P 지급(idempotent)
│   │   └─ status.js             GET   브리지 세션/SOOP 연결 상태
│   ├─ login.js            POST  KEY 로그인(숲 미사용 백업 경로)
│   ├─ attend.js           POST  출석 (BASE 400 + 연속 800 + 신규 100, Asia/Seoul)
│   ├─ open-pack.js        POST  카드팩 구매·개봉 (서버 뽑기, 시리얼 부여)
│   ├─ fuse.js             POST  카드 합성 (동일등급 3장 → 상위등급 랜덤 1장)
│   ├─ dismantle.js        POST  중복 카드 분해 → 포인트 환급
│   ├─ collection.js       POST  보유 도감 (시리얼/발행수/보상클레임 포함 옵션)
│   ├─ claim-reward.js     POST  멤버 도감 완성 보상 수령
│   ├─ cards.js            GET   전체 카드 목록(등급 포함)
│   ├─ ranking.js          POST  랭킹 (상위 50 + 내 순위)
│   ├─ announcements.js    GET   최근 UR+ 레어 드랍/합성 공지
│   └─ public-config.js    GET   공개 설정
├─ lib/                    서버 공용 (env / supabase REST / 가챠 로직 / http / 보안 / 브리지 인증)
│   ├─ gacha.js            RARITIES·PACKS·FUSE_RATES·DISMANTLE_REFUND·MEMBER_REWARDS + 뽑기/합성 판정
│   ├─ supabase.js         PostgREST 헬퍼(service_role). users/collection/serials/rewards/bridge_keys
│   ├─ bridge-auth.js      브리지 세션/토큰 쿠키(HMAC 서명, 만료 검증)
│   ├─ bridge-members.js   후원 브리지 대상 방송인 판정
│   ├─ security.js         IP/사용자별 rate limit(RPC) + 에러 헬퍼
│   └─ http.js / env.js    sendJson/readBody + .env.local 파서(dotenv 불필요)
├─ data/
│   ├─ cards.json          카드 137장 (id·member·file·rarity)
│   └─ soop-bridge-members.json   후원 브리지 대상 방송인 21명(name·soopId)
├─ assets/
│   ├─ cards/              카드 이미지 137장 (ASCII 파일명)
│   ├─ frames/             등급별 프레임 13종 SVG (c~fur)
│   ├─ packs/              팩 아트 3종
│   ├─ fx/                 MUR/FUR 스페셜 연출 영상
│   └─ card-back.jpg       카드 뒷면 로고
├─ scripts/
│   ├─ build-cards.js      cards.json 생성 + 이미지 복사
│   ├─ dev-server.js       로컬 개발 서버 (포트 3300, 의존성 0)
│   ├─ full-wipe.js        DB 완전 초기화 (자동모드 차단 → --confirm 필요)
│   ├─ grant-points.js     전체/개인 포인트 지급
│   ├─ reset-season.js     시즌 리셋
│   ├─ sync-scores.js      랭킹 점수 동기화
│   ├─ generate-frames.js  등급 프레임 생성
│   └─ provision-soop-bridge-members.js   브리지 키 DB 등록
├─ supabase/               마이그레이션 SQL 12개 (migration.sql ~ migration12_performance.sql)
├─ vercel.json             점검모드 redirect (활성 시 전 경로 → maintenance.html)
└─ .env.local              Supabase·SOOP 키 (Git 커밋 금지)
```

## 1. Supabase 마이그레이션 (1~12 순서 실행)

Supabase 콘솔 → SQL Editor → 각 파일을 순서대로 실행. 전부 idempotent(여러 번 실행해도 안전).

| # | 파일 | 내용 |
|---|---|---|
| 1 | migration.sql | 기본 테이블(users·collection·announcements) + RLS |
| 2 | migration2.sql | 멤버 도감 완성 보상(gacha_member_rewards) |
| 3-5 | migration3~5.sql | 팩/출석/점수 정책 |
| 6 | migration6_security.sql | rate limit RPC·보안 강화 |
| 7 | migration7_fuse.sql | 합성 RPC(gacha_fuse) |
| 8 | migration8_serials.sql | 카드 시리얼(넘버링) |
| 9 | migration9_soop.sql | SOOP 로그인(soop_id 컬럼) |
| 10 | migration10_soop_donations.sql | 후원 이벤트 + gacha_apply_soop_donation RPC |
| 11 | migration11_soop_bridge_keys.sql | 브리지 키 테이블(SHA-256 해시) |
| 12 | migration12_performance.sql | points default 5000·ranking 인덱스·grant_all RPC |

> RLS 정책을 만들지 않으므로 anon 접근은 전면 차단, 서버리스의 service_role 키만 통과.

## 2. 환경변수

`.env.local`(로컬) 또는 Vercel Project Settings(배포)에 등록.

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` (또는 `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`)
- `SUPABASE_SERVICE_ROLE_KEY` (또는 `SUPABASE_SECRET_KEY`)
- `SOOP_CLIENT_ID` / `SOOP_CLIENT_SECRET` — 숲 OAuth
- `SOOP_REDIRECT_URI` — 메인 로그인 콜백
- `SOOP_DONATION_REDIRECT_URI` — 후원 브리지 콜백(별도)
- `SOOP_DONATION_BRIDGE_SECRET` — 브리지 세션/토큰 HMAC 서명 키

## 3. 로컬 실행

```
node scripts/dev-server.js
```

- http://localhost:3300 접속. `.env.local` 자동 파싱(의존성 0, Node 18+).
- **실DB 연결** — 조작 시 프로덕션 데이터에 영향 주의.

## 4. Vercel 배포

1. 이 폴더를 Vercel 프로젝트로 임포트(프레임워크 프리셋 **Other**, 빌드 명령 없음).
2. 위 환경변수 전부 등록.
3. Supabase 마이그레이션 1~12 실행 완료 확인.
4. 점검 해제 = `vercel.json` 삭제 후 push(현재 점검 redirect 활성 상태).

## 게임 규칙 요약 (코드 기준)

| 항목 | 값 |
|---|---|
| 가입 보너스 | **5000P** |
| 출석 | 하루 1회 · BASE **400P** + 연속 **800P** + 신규 **100P** (Asia/Seoul, 서버 검증) |
| 일반팩 | 50P · 3장 |
| 고급팩 | 150P · 4장 · 마지막 R 이상 확정 |
| 프리미엄팩 | 500P · 5장 · 마지막 SR 이상 확정 |
| 합성 | 동일등급 3장(1장 보존·초과분) → 상위등급 1장. 성공률 C90…UR25·MUR1%(→FUR). FUR 합성 불가. 실패 시 위로금 = 분해가×3×50% |
| 분해 | 중복 카드 → 등급별 환급표(C5 … FUR250). 카드당 1장 보존 |

- 등급 13단계: C, U, R, RR, RRR, AR, CHR, HR, SR, SAR, UR, MUR, FUR
- 카드 **137장**. 뽑기/합성 판정·난수 전부 서버(암호학적 난수, 조작 방지).
- 카드 넘버링: 발행 시 시리얼(No.N) 부여, 소모 시 최신번호부터.
- UR 이상 획득(뽑기·합성) 시 전체 공지 티커 노출.
- MUR/FUR은 개봉 시 별도 2단계 스페셜 연출.
- 멤버 도감 완성 보상 = `MEMBER_REWARDS`(난이도별 차등, `lib/gacha.js`).

## 인증 방식

- **가입/로그인(기본)**: SOOP(숲) OAuth — `SOOP 숲 계정으로 시작하기` 버튼. station_name이 계정 고유키. 재로그인 시 login_key 회전(새 key 발급).
- **백업 로그인**: 발급받은 KEY 직접 입력(SOOP 미가용 시).
- **후원 브리지**: 방송인 전용 별도 OAuth(`/api/bridge/*`) — 메인 로그인과 세션 공유 안 함. 브리지 키 + 본인 SOOP 연결(double 쿠키) 필요.

## 점검모드

`vercel.json`의 redirect가 `/api/*`·`index.html`·`donation-bridge.html`을 포함한 모든 경로를 `maintenance.html`로 307. 인앱 토글은 없고, `vercel.json` 유무로만 제어(재배포 수반). 해제 = 파일 삭제 후 push.
