# Card Gacha Renewal - 작업 규칙

## 배포 절차

1. 라이브 서버나 데이터베이스부터 직접 수정하지 않는다.
2. 로컬 소스와 새 마이그레이션을 먼저 작성한다.
3. `npm test`를 통과시킨다.
4. 변경 파일만 검토해서 Git 커밋 후 `main`에 푸시한다.
5. Vercel 배포와 필요한 Supabase 마이그레이션/Edge Function 배포를 진행한다.
6. Git HEAD, Vercel 배포 커밋, Supabase 배포본을 다시 대조한다.
7. 실제 배포 직전 `npm run check:deploy`를 실행한다. 원격 `main`, 작업트리, Edge 생성본, 마이그레이션 이력이 다르면 배포하지 않는다.

## 병행 작업

- 작업 시작 전 `git fetch origin`과 `git status --short --branch`로 `HEAD == origin/main` 및 미커밋 변경 유무를 확인한다.
- 다른 작업자의 변경이 보이면 같은 파일을 수정하지 않는다. 원격이 앞섰으면 먼저 최신 커밋을 반영한다.
- 커밋 뒤 다른 커밋이 `main`에 추가되었으면 이전 커밋을 그대로 배포하지 않는다. 최신 `main`에서 다시 테스트하고 배포한다.
- Vercel, Supabase Migration, Edge Function 배포는 한 작업자가 최신 `main` 전체를 기준으로 순서대로 마무리한다.

## 월드보스 밸런스

- 운영 수치의 단일 소스는 `src/renewal/worldboss-rules.js`다.
- 월드보스 조정 시 전용 수치 파일, 관련 테스트, 새 `supabase/migrations/*.sql`만 직접 수정한다.
- `src/renewal/config.js`, `supabase/functions/_shared/generated/*`, `supabase/renewal_migration_002_catalog_and_balance.sql`에 월드보스 수치를 수동 복사하지 않는다.
- 소스 수정 후 `npm run build:edge-shared`로 Edge 생성본을 갱신한다.
- 운영 DB에 먼저 생긴 마이그레이션 버전이 발견되면 새 번호로 중복 적용하지 않는다. 운영 이력을 회수해 같은 버전 파일로 Git에 복구한다.

## 데이터베이스

- 기존 마이그레이션을 수정하거나 같은 버전 번호를 재사용하지 않는다.
- 운영 SQL을 대시보드에서 임의 실행하지 않는다. 반드시 새 `supabase/migrations/*.sql`로 남긴다.
- 보상 지급 SQL은 재실행되어도 중복 지급되지 않도록 고유 지급 이력과 충돌 방지를 둔다.
- 운영 데이터 변경 전 대상 인원과 합계를 읽기 전용 쿼리로 먼저 검증한다.

## 운영 고정값

- 신규 계정 시작 포인트 200,000P는 의도된 설정이다.
- 모험은 지역 10개, 총 100스테이지가 정상이다.
- 월드보스 보상 미수령은 자동 지급 대상으로 처리하지 않는다.

## 저장소 위생

- 사용자 ID가 포함된 통계 덤프, `.env*`, 개인 에이전트 설정을 커밋하지 않는다.
- 다른 작업자의 미추적 파일과 관계없는 변경을 삭제하거나 덮어쓰지 않는다.
