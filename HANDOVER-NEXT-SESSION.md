# 인수인계 (2026-07-12 갱신 — 대규모 패치 배포 완료)

> ⚠️ 이전 버전의 핸드오버는 "미커밋·미푸시"로 적혀 있었으나 **틀림**. 실제로는 대규모 패치 전부
> 커밋+push 완료. 이 문서는 현재 코드베이스를 기준으로 정정한 것이다.

## 상태 한 줄 요약
- **사이트 = 점검모드 유지 중** (`vercel.json` redirect → `maintenance.html`). 해제 = `vercel.json` 삭제 후 push.
- **코드 = 전부 커밋+push 완료**. `origin/main` HEAD = `68e9fa8`. 작업트리는 거의 깨끗(이 파일 + `.claude/`·`tmp/`·`tools/` untracked).
- **DB = 마이그레이션 1~12 전부 SQL 파일 존재. Supabase 실행 여부는 별도 확인 필요**(이 세션에선 DB 접근 안 함).

## 배포된 변경 (커밋 `49c3d4c` + `68e9fa8`, 이미 push 됨)

### 게임 시스템
1. **명예유스·암연시 컬렉션 삭제** → 컬렉션은 단일 `crew`(크루 21명)만. 도감 완성 보상 = 멤버별 `MEMBER_REWARDS`.
2. **카드 정리** → 구 카드 삭제 + 신규 추가 → **현재 137장** (assets 137파일과 일치 확인).
   - 분포: C18·U12·R11·RR8·RRR8·AR8·CHR7·HR8·SR18·SAR14·UR14·MUR7·FUR4
3. **합성 시스템** (`api/fuse.js` + `lib/gacha.js:resolveFuse` + `migration7_fuse.sql`):
   - 동일등급 3장(각 1장 보존, 초과분만) → 상위등급 랜덤 1장. 실패 시 위로금 = `분해가×3×50%`.
   - 성공률: C90·U85·R80·RR75·RRR70·AR60·CHR55·HR50·SR40·SAR35·UR25·**MUR 1%**(→FUR). **FUR은 합성 불가**.
   - 판정·결과카드 전부 서버(`secureRandom`).
4. **팩 상급확률 절반** → SR~FUR 가중치 ÷2 (normal·premium·luxury 전부). 가격 = 50/150/500 P.
5. **카드 넘버링(시리얼)** (`migration8_serials.sql`): 발행 시 `No.N`, 소모 시 최신번호부터. graceful fallback(migration8 전이면 생략).

### 인증
6. **SOOP(숲) OAuth 로그인** (`api/auth/soop-start.js`·`soop-callback.js` + `migration9_soop.sql`):
   - 가입 = 숲 OAuth 단일 경로(`api/register.js` 삭제됨). 로그인 = 숲 or 발급 key(백업).
   - `soop_id`(=station_name) = 고유키, `nickname`(=user_nick) 로그인마다 갱신, 재로그인 시 login_key 회전(새 key 발급).
   - 콜백은 key를 URL fragment(`/#soop=KEY`)로 전달 → 서버 로그/리퍼러에 안 남음.

### 후원 브리지 (이전 핸드오버에 누락된 신규 기능)
7. **방송인 SOOP 별풍선 → P 포인트 브리지** (`api/bridge/*` + `donation-bridge.html` + `migration10/11`):
   - 별도 OAuth 플로우(`/api/bridge/soop-start` ≠ 메인 `/api/auth/soop-start`). redirect_uri도 별도 변수 `SOOP_DONATION_REDIRECT_URI`.
   - `gacha_soop_donation_events`(idempotent, 동시후원 교착방지 advisory lock) + `gacha_apply_soop_donation` RPC.
   - 후원 시점에 **양쪽 계정 모두 가입되어 있어야** 지급(미가입은 적립 안 함 — 보류 포인트 폐기됨).
   - 브리지 접근 = `gacha_soop_bridge_keys` 키(SHA-256 해시만 저장) + 방송인 본인 SOOP 연결(double 세션/토큰 쿠키, `lib/bridge-auth.js` HMAC).
   - 대상 방송인 21명 = `data/soop-bridge-members.json`(크루 전원). `login.js`의 `canUseDonationBridge` 플래그로 메인 화면 버튼 노출.

### 성능/운영 (`migration12_performance.sql`)
8. `gacha_users.points` default 5000, ranking 인덱스, `gacha_get_ranking`(상위50+내순위)·`gacha_grant_all_points`(전체 지급 atomic) RPC.

## 현재 포인트/보상 수치 (코드 기준 — 핸드오버 구버전 수치는 틀림)
| 항목 | 값 | 위치 |
|---|---|---|
| 가입 보너스 | **5000P** | `lib/supabase.js:82,114`, `migration12` default |
| 출석 | **BASE 400 + 연속 800 + 신규 100** | `api/attend.js:7-9` |
| 팩 | normal 50P/3장 · premium 150P/4장(R확정) · luxury 500P/5장(SR확정) | `lib/gacha.js:25-38` |
| 분해 환급 | C5 … FUR250(최대) | `lib/gacha.js:41-44`, `index.html:637` |

> 이전 핸드오버의 "가입 2000P"·README의 "1000P/200P"·`maintenance.html`은 모두 **구 수치**.

## 배포/오픈 절차
1. **코드는 이미 push 됨** → Vercel 자동배포 됨(점검 redirect가 가려줌).
2. **Supabase**: 아직 migration 7~12 실행 안 했을 수 있음. SQL Editor에서 **7 → 8 → 9 → 10 → 11 → 12 순서**로 실행(각각 idempotent).
3. **Vercel 환경변수** 확인:
   - 기존: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`/`NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY`/`SUPABASE_SECRET_KEY`
   - SOOP: `SOOP_CLIENT_ID`, `SOOP_CLIENT_SECRET`, `SOOP_REDIRECT_URI`(메인), `SOOP_DONATION_REDIRECT_URI`(브리지)
   - 브리지 서명: `SOOP_DONATION_BRIDGE_SECRET`
4. **검증** → `vercel.json` 삭제 후 push = 사이트 오픈.

## 대기 (최후순위)
- 카드 등급 전면 재배치 + 도감보상 재계산 → 사용자 카드 수집 끝난 후.
- 교환 시스템 = **취소됨**. 확률공시 페이지 = **만들지 않음**(사용자 지시).

## 금지
- `cards.json` 기존 엔트리 변경 금지(append만). 뽑기확률 임의변경 금지. `.env.local` 값 출력 금지.
- DB 대량삭제는 자동모드가 차단 → 사용자가 CMD에서 `node scripts/full-wipe.js --confirm` 직접 실행.
- 브랜드 표기 = **"Calm MonstarZ" / "캄몬스타즈"** 만.

## 참고
- 로컬: `node scripts/dev-server.js` (포트 3300, 실DB 연결 주의).
- 포인트 지급: `node scripts/grant-points.js <액수> --confirm`.
- 브리지 멤버 프로비저닝: `node scripts/provision-soop-bridge-members.js`.
- 크루 21명 로스터 = `data/soop-bridge-members.json` + `MEMBER_ORDER`(`index.html:636`).

## 이번 세션에서 수정한 것
- `index.html`: `renderCollection` **중복 선언(데드코드) 제거** — 931~969행 구버전이 무시되고 있었음. (핸드오버 구버전이 지적한 934행 `includeDetails` 누락은 이 데드코드 안이라 무효였음. 실제 동작 버전은 정상.)
