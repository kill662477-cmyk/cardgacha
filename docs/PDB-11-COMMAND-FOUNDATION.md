# PDB-11 서버 명령 기반·전투 편성 RPC

## 목적

시즌2 상태 변경을 클라이언트 직접 저장이 아닌 service role 전용 원자 RPC로 전환한다. 첫 명령은 `updateFormation`이다.

## 파일

- SQL: `supabase/renewal_migration_003_command_foundation.sql`
- 계약: `src/renewal/service-contract.js`
- 정적 검증: `tests/renewal-command-foundation.test.js`

운영 Supabase에는 아직 실행하지 않았다.

## 추가 테이블

### `gacha_s2_collection_records`

한번 획득한 카드를 영구 기록한다. 재료 소모로 `gacha_s2_player_cards` 보유 행이 사라져도 도감 등록은 유지된다.

### `gacha_s2_command_audit`

성공한 명령의 사용자, 명령 ID, 명령 종류, 요청 해시, 예상 revision, 커밋 revision을 기록한다. 동일 계정의 명령 ID 재사용은 unique 제약으로 차단한다.

두 테이블 모두 RLS를 켜고 공개 직접 접근을 막는다.

## 공통 함수

- `gacha_s2_now_ms`: 서버 시각을 epoch millisecond로 반환
- `gacha_s2_get_player_snapshot`: 계정·상태·카드·도감 기록을 서버 응답 형태로 조립
- `gacha_s2_command_error`: 계약 버전 1 오류 응답 생성

스냅샷은 서버 권위 필드다. `currentStage`, `soundEnabled`, `autoBattle` 같은 로컬 UI 캐시는 이후 Supabase 어댑터가 합친다.

## `gacha_s2_update_formation`

입력:

- 사용자 UUID
- 예상 revision
- 8~128자 멱등성 키
- 카드 ID 1~5개

처리 순서:

1. 입력 형식과 중복 카드 ID 검사.
2. 요청 내용을 DB에서 SHA-256으로 계산. 호출자가 해시를 주입하지 못함.
3. 사용자 상태 행 `FOR UPDATE` 잠금.
4. 같은 멱등성 키가 있으면 같은 요청은 최초 응답 재생, 다른 요청은 `IDEMPOTENCY_KEY_REUSED`.
5. revision 불일치는 상태를 바꾸지 않고 `VERSION_CONFLICT`와 최신 스냅샷 반환.
6. 실제 보유 수량과 서버 카탈로그를 대조해 미보유·EX 카드 거부.
7. 편성과 revision을 함께 갱신.
8. 응답, 24시간 멱등성 기록, 영구 감사 로그를 같은 트랜잭션에 저장.

성공한 명령만 revision이 정확히 1 증가한다. 서비스 역할만 실행 가능하다.

## 다음

같은 기반을 사용해 카드팩 구매와 강화 RPC를 구현한다. 팩은 포인트 차감·서버 추첨·카드/도감 지급, 강화는 EXP 게이트·재료·아이템·포인트·성공/파괴 판정을 각각 한 트랜잭션으로 처리한다.
