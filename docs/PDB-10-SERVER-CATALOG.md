# PDB-10 서버 카드 카탈로그·밸런스 스냅샷

## 목적

카드 보유, 편성, 팩 추첨, 강화와 전투 판정을 브라우저 JSON만 믿고 처리하지 않도록 시즌2 서버 권위 카탈로그를 고정한다.

## 파일

- 원본 카드: `data/renewal-cards.json`
- 원본 밸런스: `src/renewal/config.js`
- 생성기: `scripts/build-renewal-database-catalog.js`
- 결과 SQL: `supabase/renewal_migration_002_catalog_and_balance.sql`
- 정적 검증: `tests/renewal-database-catalog.test.js`

생성 명령:

```powershell
npm.cmd run build:database-catalog
```

카드나 밸런스를 변경한 뒤 SQL을 재생성하지 않으면 자동 테스트가 실패한다.

## 테이블

### `gacha_s2_balance_versions`

- 밸런스 버전별 전체 서버 설정 JSONB 저장
- 설정 SHA-256과 카드 카탈로그 SHA-256 저장
- 부분 unique index로 활성 버전은 정확히 하나만 허용
- RLS 활성화, `public`, `anon`, `authenticated` 직접 접근 금지

### `gacha_s2_card_catalog`

- 카드 ID, 멤버, 자산 파일, 등급, 종족, 전투 유형, 시즌1 원본 등급, 단체사진 여부 저장
- 전투 카드: F~SSS, 저그·테란·프로토스, 8개 전투 유형
- EX 카드: 종족 `EX`, 전투 유형 없음, 단체사진만 허용
- `gacha_s2_player_cards.card_id`가 카탈로그를 참조하도록 FK 연결
- RLS 활성화, 공개 직접 쓰기 금지

로컬 테스트용 `enhancement`, `exp`, `copies` 값은 카탈로그에 넣지 않는다. 실제 보유 수량·강화·EXP는 사용자별 `gacha_s2_player_cards`에만 저장한다.

## 현재 고정값

- 밸런스: `2026.07.18-random-loot-1`
- 전체 212장
- 전투 카드 204장, EX 8장
- F~S 각 24장, SS 22장, SSS 14장
- 각 전투 등급에 8개 전투 유형 전부 존재

## 실행 순서

1. `renewal_migration_001_accounts_reset.sql` 스키마와 import 검증.
2. `renewal_migration_002_catalog_and_balance.sql` 실행.
3. 전체 212행, 등급 수량, EX 8행, 해시와 활성 버전 확인.
4. 편성·팩·강화 서버 RPC 구현.

운영 Supabase에는 아직 실행하지 않았다.
