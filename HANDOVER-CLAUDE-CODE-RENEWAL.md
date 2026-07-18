# 카드가챠 시즌2 리뉴얼 - Claude Code 상세 인수인계

> 갱신: 2026-07-19 KST (SOOP 숲 로그인 복구 Phase 1+2 완료)
> 작업 폴더: `C:\Users\silve\OneDrive\Desktop\card-gacha-renewal`
> 브랜치: `renewal`
> 현재 HEAD: `ec96103 feat: restore SOOP user login (Phase 1 maintenance mode + Phase 2 soop-auth)`
> 직전 커밋: `90a8beb feat: add maintenance mode toggle for SOOP auth restoration`

## 0. 사용자 지시

- 현재 작업은 즉시 중단했다.
- 로컬 개발 서버 3300/3301은 모두 종료했다.
- 사용자가 다시 지시하기 전까지 push, 배포, 운영 Supabase migration, 운영 데이터 변경 금지.
- 이번 범위는 작업 1~8까지다. 작업 9는 절대 시작하지 않는다.
- 작업 9에는 백업, 실제 cutover, 배포, 시즌1 DB 삭제가 포함된다.
- `supabase/renewal_migration_999_drop_season1.sql`은 특히 실행 금지.
- 사용자 작업 또는 기존 변경을 reset/checkout/clean으로 제거하지 않는다.

## 1. 현재 Git 상태

커밋된 최신 작업:

```text
ec96103 feat: restore SOOP user login (Phase 1 maintenance mode + Phase 2 soop-auth)
90a8beb feat: add maintenance mode toggle for SOOP auth restoration
dce54f8 chore: local QA profile with full roster and no-cache dev server
d9e13e6 feat: add live ranking and SOOP bridge
dbdc83a feat: route game UI through server commands
c2c01f3 feat: bridge legacy login keys to Supabase Auth
6b58d06 feat: add remaining economy and profile commands
```

미커밋 파일 없음. 워킹트리 클린.

미커밋 변경 의미:

1. `scripts/dev-server.js`
   - 모든 정적 파일 응답을 `Cache-Control: no-cache`로 변경했다.
   - 로컬 UI 검증 중 JS/CSS 1시간 캐시 때문에 수정이 반영되지 않던 문제 대응이다.
2. `src/renewal/local-test-profile.js`
   - 최초 로컬 QA 계정 MSTZ에 전체 카드 1장씩, 전체 도감 등록을 넣었다.
   - 포인트는 기존 요구대로 1,000,000P다.
3. `tests/renewal-content.test.js`
   - 위 로컬 QA 프로필 요구에 맞춰 테스트 기대값을 수정했다.

이 3개 변경은 아직 최종 브라우저 검증도, 테스트도, 커밋도 하지 않았다. 먼저 diff를 확인하고 이어서 검증할 것.

```powershell
git status --short
git diff -- scripts/dev-server.js src/renewal/local-test-profile.js tests/renewal-content.test.js
```

## 2. 작업 1~9 진행 상태

| 번호 | 작업 | 상태 |
|---:|---|---|
| 1 | 누락 RPC 및 서버 권한 기반 명령 구현 | 완료 |
| 2 | 시즌1 로그인 키를 Supabase Auth로 교환 | 완료 |
| 3 | 게임 UI를 서버 명령 기반으로 전환 | 완료 |
| 4 | 서버 랭킹, 월드보스 Realtime, SOOP 브릿지 | 완료 |
| 5 | 로컬/프리뷰 UI 및 기능 검증 | 완료 (2026-07-18) |
| 6 | 시즌1 이관 dry-run 검증 | 완료 (오프라인 fixture) |
| 7 | 보안, 동시성, 부하 검증 | 완료 (정적+결정론 harness, 실부하 제외) |
| 8 | 전체 UI/UX 플레이테스트 및 문서 최신화 | 완료 |
| 9 | 백업, 실제 이관, 배포, 시즌1 DB 삭제 | 금지, 시작하지 말 것 |

작업 5~8 검증 결과는 15절 참조. push·배포·운영 migration은 하지 않았다.

## 3. 완료된 서버 기능

### 작업 1: 서버 명령/RPC

- 카드팩 구매 및 10회 구매
- 강화 시도와 서버 확률 판정
- 모험 시작/빠른 전투/보상
- 미니게임 결과 검증 및 일일 한도
- 월드보스 회차, 공격, 보상
- 상점 아이템과 지원 아이템
- 카드 경험치 포션
- 모험 시작 초기화권, 빠른 전투 초기화권
- 대표 카드와 프로필 관련 명령
- 계정 revision 기반 동시 수정 충돌 처리
- 서비스 역할 전용 RPC와 RLS 제한

핵심 migration:

```text
renewal_migration_001_accounts_reset.sql
renewal_migration_002_catalog_and_balance.sql
renewal_migration_003_command_foundation.sql
renewal_migration_004_pack_and_enhancement.sql
renewal_migration_005_adventure_and_minigames.sql
renewal_migration_006_world_boss.sql
renewal_migration_007_economy_profile.sql
renewal_migration_008_auth_bridge.sql
renewal_migration_009_live_services.sql
```

### 작업 2: 로그인 전환

- 시즌1 로그인 키 검증 후 Supabase Auth 세션으로 교환한다.
- 로그인 키 원문은 DB에 저장하지 않고 기존 해시 검증을 사용한다.
- 일회성 교환 코드를 사용한다.
- 브라우저에 service role key나 SOOP client secret을 노출하지 않는다.
- 주요 파일:
  - `supabase/functions/session-exchange/index.ts`
  - `src/renewal/remote-runtime.js`
  - `supabase/renewal_migration_008_auth_bridge.sql`

### 작업 3: UI 서버 명령 전환

- 원격 모드에서 클라이언트가 포인트, 카드, 보상을 직접 확정하지 않는다.
- `supabase/functions/game-command/index.ts`가 JWT 사용자를 고정한다.
- `src/renewal/server-command-router.js`가 명령을 검증하고 service-role RPC를 호출한다.
- `src/renewal/supabase-game-service.js`가 UI와 Edge 명령을 연결한다.
- 로컬 모드는 QA용 `local-game-service`를 유지한다.

### 작업 4: 라이브 서비스

커밋 `d9e13e6`에 포함:

- 서버 계산 전투력 랭킹 RPC `gacha_s2_get_power_ranking`
- 월드보스 서버 상태와 실시간 랭킹
- Supabase Realtime 구독과 10초 보조 새로고침
- 스트리머 브릿지 상태 조회
- 브릿지 키 인증과 IP-HMAC 제한: 15분당 8회
- SOOP 후원 이벤트 중 다음만 인정:
  - `BALLOON_GIFTED`
  - `BATTLE_MISSION_GIFTED`
- `FINISHED`, `SETTLED`는 제외
- 별풍선 1개당 후원자와 방송인 각각 3P
- 방송인 수령 계정은 활성 브릿지의 SOOP ID로 고정
- event ID 멱등성, payload 충돌 탐지, advisory lock, revision 처리
- SOOP 임시 토큰 AES-GCM 암호화
- OAuth 교환 코드는 일회성 소비
- 신규 파일:
  - `bridge.html`
  - `src/renewal/soop-bridge.js`
  - `styles/renewal/bridge.css`
  - `supabase/functions/soop-bridge/index.ts`
  - `supabase/renewal_migration_009_live_services.sql`

## 4. 마지막 검증 결과

작업 4 완료 직후:

- `npm.cmd test`: 전체 통과
- 다음 Edge 함수 Deno typecheck 통과:
  - `game-command`
  - `session-exchange`
  - `soop-bridge`
- 사용 명령:

```powershell
npx.cmd -y deno-bin@2.2.7 check --config supabase/functions/game-command/deno.json supabase/functions/game-command/index.ts
npx.cmd -y deno-bin@2.2.7 check --config supabase/functions/session-exchange/deno.json supabase/functions/session-exchange/index.ts
npx.cmd -y deno-bin@2.2.7 check --config supabase/functions/soop-bridge/deno.json supabase/functions/soop-bridge/index.ts
```

주의:

- 미커밋 QA 프로필/캐시 변경 후에는 아직 테스트를 다시 돌리지 않았다.
- Docker가 설치되지 않아 로컬 Supabase Postgres 실행 검증은 못 했다.
- 운영 DB에는 어떤 migration도 실행하지 않았다.
- 실제 SOOP 자격증명이 없어 OAuth/ChatSDK 실연동은 하지 않았다.

## 5. 작업 5 중단 지점과 재개 순서

중단 직전 상태:

- 인앱 브라우저로 `http://127.0.0.1:3300/#adventure`를 열었다.
- 첫 데스크톱 화면은 렌더링 정상, 큰 겹침 없음.
- MSTZ와 1,000,000P는 보였지만 전투력 0, 편성 없음으로 나왔다.
- 원인은 로컬 QA 프로필이 카드 0장/도감 0으로 초기화되던 것이었다.
- 전체 카드 1장/전체 도감으로 미커밋 수정했다.
- 재로딩해도 기존 JS 캐시가 남아 `dev-server.js`를 no-cache로 수정했다.
- 그 직후 사용자가 중단을 지시했다. 수정 반영 후 브라우저 재검증은 아직이다.

재개 절차:

```powershell
cd C:\Users\silve\OneDrive\Desktop\card-gacha-renewal
npm.cmd test
npm.cmd run dev
```

브라우저에서 `http://127.0.0.1:3300/?fresh#adventure` 접속 후 확인:

1. 닉네임 `MSTZ`
2. 포인트 `1,000,000P`
3. 전체 카드 1장씩 보유
4. 전체 도감 등록
5. 자동 편성 5장과 전투력 0 초과
6. 새로고침 후 현재 hash 메뉴 유지
7. 편성 변경 버튼 작동
8. 카드가 전투력 내림차순으로 표시

모든 메뉴 점검:

- 상점: 상품 전체 노출, x1/x10, 투명 카드팩 이미지, 고등급 수동 오픈 흐름
- 강화: 카드 EXP 조건, 재료, 성공률, 9성 난이도, 성공/실패 FX
- 도감: 사람별 정렬, 미등록 카드백, 도감 50%/30% 전투 보너스
- 랭킹: 전투력 랭킹만, 내 순위와 서버 값
- 모험: 4시간당 3회, 매번 1단계부터, 실패 시 종료, 중앙 전투 카드
- 월드보스: 17/18/19/20시, 30분 전투+30분 결과, 누적 보상
- 미니게임: 카드짝맞추기와 캄몬사과게임, 각 일일 7,500P 한도
- API: 원격 스트리머 계정에만 버튼 노출, 로컬 브릿지 페이지 오류 없이 표시

화면 크기:

- 데스크톱 1280x720 이상
- 모바일 가로 844x390
- 모바일 가로 740x360

확인 항목:

- 가로 overflow
- 버튼/텍스트 겹침
- 모달 잘림
- 카드 비율 왜곡
- 콘솔 error/warn
- 새로고침 시 메뉴 유지

작업 5 완료 후 미커밋 3파일을 테스트하고 별도 로컬 커밋하는 것이 안전하다. push는 금지다.

## 6. 작업 6: 시즌1 이관 dry-run

실제 운영 DB 연결 없이 fixture/익명화 데이터로 먼저 실행한다.

관련 파일:

- `scripts/dry-run-season1-import.js`
- `tests/renewal-season1-import.test.js`
- `docs/PDB-8-SEASON1-MIGRATION-SPEC.md`
- `supabase/renewal_migration_001_accounts_reset.sql`

검증 규칙:

1. 카드 오픈 0회인 일반 계정은 삭제 대상
2. 스트리머 계정은 카드 오픈 0회여도 유지
3. 로그인 정보, UUID, 닉네임, SOOP ID, 브릿지 정보 유지
4. 포인트, 카드, 도감, 강화, 편성, 모험, 미니게임, 월드보스 상태 초기화
5. 기본 시작 포인트 5,000P
6. 시즌1 스냅샷 보상:
   - 1~10위 +30,000P
   - 11~20위 +20,000P
   - 21~30위 +15,000P
   - 31~40위 +10,000P
   - 41~50위 +5,000P
7. 삭제/유지/스트리머/랭커/중복/누락 수량 보고
8. 실제 import와 999 삭제는 실행하지 않음

명령 확인:

```powershell
npm.cmd run dry-run:season1-import
node tests/renewal-season1-import.test.js
```

스크립트가 운영 환경변수를 자동으로 읽는지 먼저 소스 확인할 것. 운영 연결 가능성이 있으면 fixture 입력 전용 옵션을 추가한 뒤 실행한다.

## 7. 작업 7: 보안·동시성·부하 검증

보안:

- 클라이언트 정적 파일에 service-role key, SOOP client secret, 브릿지 원문 키가 없는지 검색
- RLS와 `GRANT/REVOKE` 검토
- 모든 Edge 명령에서 JWT 사용자 ID 강제
- CORS allowlist 검증
- 브릿지 인증 제한, 후원 이벤트 제한, event ID 멱등성 검증
- OAuth state와 일회성 교환 만료 검증
- 만료된 OAuth exchange row 정리 전략 확인

동시성:

- 같은 pack purchase request ID 동시 요청
- 같은 enhancement request ID 동시 요청
- adventure/minigame 보상 중복 요청
- 월드보스 동시 공격과 3회 제한
- 월드보스 보상 중복 수령
- SOOP 동일 event ID 중복 수신
- 같은 event ID에 다른 payload 수신 시 거부
- 다중 기기 revision 충돌

부하:

- 랭킹 조회
- 월드보스 17시 집중 공격
- Realtime 구독 증가
- SOOP 이벤트 burst
- 상점 x10 구매

운영이나 프리뷰 자격증명이 없으면 정적 테스트와 결정론적 로컬 harness까지만 한다. 실제 부하를 운영에 보내면 안 된다. 제한 사항을 문서에 남긴다.

## 8. 작업 8: 최종 플레이테스트와 문서화

작업 5~7 수정이 끝난 뒤 전체 회귀 테스트:

```powershell
npm.cmd test
npm.cmd run simulate:renewal-balance
git diff --check
```

Edge Deno check도 다시 실행한다.

최신화 대상:

- `HANDOVER-CLAUDE-CODE-RENEWAL.md`
- `RENEWAL-PLAN-2-IDLE-RPG.md`
- `docs/PDB-8-SEASON1-MIGRATION-SPEC.md`
- `docs/PDB-15-SUPABASE-GAME-SERVICE.md`
- `production/session-state/active.md`
- 필요한 migration/runbook 문서

문서에 반드시 기록:

- migration 실행 순서 001~009
- 999는 최종 백업·복구 검증·전환 완료 뒤에만 실행
- push/배포/운영 migration을 하지 않았다는 사실
- Docker 부재로 로컬 Postgres 실행 검증을 못 한 경우 그 제한
- SOOP 실자격증명 부재로 live OAuth를 못 한 경우 그 제한
- 작업 9에 필요한 정확한 체크리스트

필요 환경변수:

```text
GAME_ALLOWED_ORIGINS
AUTH_RATE_LIMIT_PEPPER
SOOP_BRIDGE_SESSION_SECRET
SOOP_BRIDGE_RATE_LIMIT_PEPPER
SOOP_BRIDGE_ENCRYPTION_KEY
SOOP_DONATION_CLIENT_ID
SOOP_DONATION_CLIENT_SECRET
SOOP_DONATION_REDIRECT_URI
SOOP_BRIDGE_PAGE_URL
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
```

## 9. 금지된 다음 단계

아래는 사용자 명시 허가 전 실행 금지:

1. 운영 Supabase 백업/복원 시험
2. 운영 migration 001~009 실행
3. 실제 시즌1 계정 import
4. DNS/환경변수/cutover 변경
5. Git push
6. GitHub/Vercel/Sites 배포
7. 점검 페이지 해제
8. `renewal_migration_999_drop_season1.sql` 실행
9. 시즌1 테이블/파일/DB 삭제

## 10. 알려진 위험과 확인점

- migration 009는 정적 테스트만 통과했고 실제 Postgres에서 실행하지 않았다.
- SOOP OAuth는 실제 client 자격증명 없이 E2E 검증하지 않았다.
- 후원 이벤트 count 조회 오류 처리와 만료 OAuth exchange 정리 여부를 작업 7에서 재검토한다.
- 전투력 랭킹 동률 정렬이 안정적인지 부하/동시성 테스트에서 확인한다.
- Realtime은 표시 갱신용이다. 보상과 순위 판정 근거는 서버 RPC만 사용한다.
- 브라우저 시계나 localStorage 값으로 포인트/보상/월드보스 결과를 확정하면 안 된다.
- 로컬 QA 프로필 변경은 신규 revision 0 저장에만 적용된다. `?fresh`로 초기화해 확인한다.

## 11. 바로 재개할 첫 명령

```powershell
cd C:\Users\silve\OneDrive\Desktop\card-gacha-renewal
git status --short
git diff --check
npm.cmd test
npm.cmd run dev
```

작업 5~8은 2026-07-18 완료되었다(15절). 다음 세션의 남은 작업은 작업 9 진입 준비뿐이며, 사용자 명시 허가 전에는 시작하지 않는다.

## 15. 작업 5~8 검증 결과 (2026-07-18)

푸시·배포·운영 migration 없이 로컬에서만 진행했다.

### 작업 5 — 로컬 UI/기능 검증

- dev 서버 `scripts/dev-server.js` 포트 3300, 인앱 브라우저로 `?fresh` 접속.
- QA 프로필 정상: MSTZ, 카드 212종 보유, 도감 212 등록, 1,000,000P, 편성 전투력 269,297.
- 7개 메뉴(상점·강화·도감·랭킹·모험·월드보스·미니게임) 전부 렌더, 콘솔 error/warn 0.
- 가로 overflow 0: 데스크톱 1280, 모바일 가로 844x390·740x360 전 화면.
- 편성 다이얼로그 정상, 인벤토리 전투력 내림차순. 상점 일반/정예/프리미엄/종족 팩 x1·x10 노출.

### 작업 6 — 시즌1 이관 dry-run

- `scripts/dry-run-season1-import.js`는 완전 오프라인이다. 로컬 JSON `--input`만 읽고 `http(s)` 입력은 거부한다. Supabase 연결·env 사용 없음.
- 합성(익명) fixture로 실행: 미개봉 비스트리머 삭제, 스트리머 유지, 기본 5,000P, top50 랭크 보상(30k/20k/15k/10k/5k), 카드 상태 초기화, 시리얼 폐기, 브릿지 유지, 중복 SOOP ID·잘못된 키 해시·미등록 카드 차단을 모두 확인.
- 클린 fixture: `ok:true`, 유지 66 / 삭제 54 / 스트리머 6 / 5,000×66=330,000 기본 + 570,000 랭크보너스. 불량 fixture: 에러로 차단.
- `tests/renewal-season1-import.test.js` 통과.

### 작업 7 — 보안·동시성·부하 (정적)

- 클라이언트 제공 파일(index.html, bridge.html, src/renewal, styles) 비밀키 스캔 0건. service-role/SOOP secret/암호화키/브릿지 원문키/JWT 리터럴 없음.
- Edge 3함수(game-command, session-exchange, soop-bridge) 전부 `auth: 'user'` + `userClaims.id` 강제, 미인증 401. CORS는 `GAME_ALLOWED_ORIGINS` allowlist로 게이트(미허용 origin에 `Access-Control-Allow-Origin` 미부여).
- 동시성/멱등성: 결정론 테스트가 double-click lock, idempotency replay, revision conflict, 원자 경제, 월드보스 원자 공유 HP, SOOP event ID 멱등성을 커버(전부 통과).
- 실부하 테스트는 운영/프리뷰 자격증명 부재로 미실시(정적+결정론 harness까지). 운영 부하 검증은 작업 9 이후 별도.

### 작업 8 — 회귀·문서

- `npm test` 전체 통과, `npm run simulate:renewal-balance` 정상(완주 상위 13일·중위 28일·하위 미완주로 분리), `git diff --check` 클린.
- Edge 3함수 Deno typecheck 통과(`deno-bin@2.2.7 check`).
- 본 문서와 `production/session-state/active.md` 최신화.

남은 제한: 실제 Postgres 실행 검증(Docker 부재), 실 SOOP OAuth E2E, 운영 부하 — 전부 작업 9 이후.
