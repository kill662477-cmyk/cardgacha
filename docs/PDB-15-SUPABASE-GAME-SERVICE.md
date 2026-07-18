# PDB-15 Supabase 게임 서비스·Edge 명령 라우터

## 범위

- 브라우저 어댑터: `src/renewal/supabase-game-service.js`
- 서버 라우터: `src/renewal/server-command-router.js`
- Edge Function: `supabase/functions/game-command/index.ts`
- Edge 설정: `supabase/config.toml`, `supabase/functions/game-command/deno.json`
- 공용 엔진 동기화: `scripts/build-edge-shared.mjs`
- 상태: 로컬 구현·단위/정적 검증 완료. Supabase 실행·배포·UI 전환 미실행

## 인증 경계

- 브라우저에는 project URL, publishable key, 사용자 access token만 둔다.
- secret/service-role key를 브라우저 설정·번들·요청 본문에 넣지 않는다.
- `game-command`는 `verify_jwt = false`로 두되 모든 POST에서 `createSupabaseContext(req, { auth: 'user' })`로 사용자 JWT를 직접 검증한다.
- 사용자 ID는 요청 본문에서 받지 않고 검증된 `userClaims.id`로 고정한다.
- service-role DB 접근은 Edge의 `supabaseAdmin` 내부에서만 사용한다.
- `GAME_ALLOWED_ORIGINS` 허용 목록, POST 전용, 128KiB 본문 제한, `no-store`를 적용한다.

## 요청 종류

| kind | 역할 |
|---|---|
| `snapshot` | 인증 계정의 서버 스냅샷 조회 |
| `worldBossStatus` | 공동 HP·개인 기록·TOP 10 조회 |
| `command` | `service-contract.js` 형식의 변경 명령 실행 |

## 명령 라우팅

직접 DB 판정:

- 편성 변경
- 카드팩 구매
- 강화
- 모험 런 정산
- 미니게임 시작·정산
- 월드보스 결과 보상

Edge 검증 후 DB 원자 반영:

- 모험 시작
- 빠른 전투
- 월드보스 공격

Edge 검증 명령은 서버 스냅샷의 보유 카드·강화·영구 도감으로 편성과 보너스를 재구성한다. DB 활성 밸런스 버전과 Edge 엔진 버전이 다르면 실패 처리한다. 모험 클리어 수와 월드보스 피해·SHA-256 검증 해시는 Edge가 만들며 브라우저 값은 받지 않는다.

## 공용 엔진

`npm.cmd run build:edge-shared`가 카드 데이터와 아래 원본을 `supabase/functions/_shared/generated`에 복제한다.

- 설정·전투·도감·월드보스 스케줄/규칙
- 명령 계약·서버 명령 라우터
- 카드 212장 데이터

테스트는 원본과 생성본을 바이트 단위로 비교한다. 원본 변경 뒤 동기화하지 않으면 실패한다.

## 남은 연결

- 시즌1 로그인 키를 Supabase Auth 세션으로 교환하는 계정 연동 경계
- `app.js`의 로컬 선계산·`persistSnapshot` 호출을 원격 명령 결과 기반으로 순차 교체
- 아직 DB RPC가 없는 오프라인 보상·지원 아이템·초기화권·대표카드·잠금·EX 수령
- 전투력 랭킹 서버 조회
- Supabase CLI/Deno 로컬 실행, preview DB 통합 테스트, CORS 운영 도메인 설정

계정 인증과 누락 RPC가 준비되기 전에는 `app.js`에서 원격 어댑터를 활성화하지 않는다.
