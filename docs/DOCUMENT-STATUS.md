# 시즌2 문서 상태

> 최종 동기화: 2026-07-18
> 현재 작업 범위: 로컬 migration·테스트·커밋 허용. push·배포·운영 DB 실행 금지

## 실행 기준

수치나 상태가 충돌하면 다음 순서로 판단한다.

1. `src/renewal/config.js`, `src/renewal/state-schema.js`
2. `docs/PDB-2-BALANCE-LOCK-2026-07-17.md`, `docs/PDB-3-GAME-STATE-SCHEMA-V2.md`
3. `HANDOVER-CLAUDE-CODE-RENEWAL.md`
4. `production/session-state/active.md`의 최하단 최신 항목
5. `RENEWAL-PLAN-2-IDLE-RPG.md`, `RENEWAL-IMPLEMENTATION-ROADMAP.md`

## 현재 문서

- `HANDOVER-CLAUDE-CODE-RENEWAL.md`: 다음 작업자가 먼저 읽는 최신 인수인계
- `RENEWAL-PLAN-2-IDLE-RPG.md`: 확정 게임 규칙과 화면 기획
- `RENEWAL-IMPLEMENTATION-ROADMAP.md`: 구현 단계와 DB 진입 전 순서
- `RENEWAL-GAME-CONCEPT.md`: 초기 컨셉 중 현재 채택·보류 범위
- `docs/RENEWAL-PRE-DATABASE-WORKLIST.md`: DB 진입 상태와 남은 운영 검증 체크리스트
- `docs/PDB-8-SEASON1-MIGRATION-SPEC.md`: 시즌1 계정·브릿지 선별 이관, 초기화, 랭커 보상, 최종 삭제 기준
- `docs/PDB-10-SERVER-CATALOG.md`: 서버 권위 카드 212장·밸런스 버전·생성·검증 기준
- `docs/PDB-11-COMMAND-FOUNDATION.md`: 멱등성·revision 명령 기반, 영구 도감, 감사 로그, 편성 RPC
- `docs/PDB-12-PACK-ENHANCEMENT-RPC.md`: 서버 난수 카드팩 구매·강화 원자 처리와 감사 기준
- `docs/PDB-13-ADVENTURE-MINIGAME-RPC.md`: 모험 검증·빠른 전투·서버 보드 미니게임 원자 처리 기준
- `docs/PDB-14-WORLD-BOSS-RPC.md`: KST 월드보스 회차·공동 HP·개인 시도·결과 보상 기준
- `supabase/renewal_migration_001_accounts_reset.sql`: 리뷰용 시즌2 계정·브릿지 이관 migration, 운영 미실행
- `supabase/renewal_migration_002_catalog_and_balance.sql`: 생성형 카드·밸런스 카탈로그 migration, 운영 미실행
- `supabase/renewal_migration_003_command_foundation.sql`: 서버 스냅샷·명령 기반·편성 RPC migration, 운영 미실행
- `supabase/renewal_migration_004_pack_and_enhancement.sql`: 카드팩 구매·강화 RPC migration, 운영 미실행
- `supabase/renewal_migration_005_adventure_and_minigames.sql`: 모험·빠른 전투·미니게임 RPC migration, 운영 미실행
- `supabase/renewal_migration_006_world_boss.sql`: 월드보스 회차·공동 HP·공격·보상 RPC migration, 운영 미실행
- `supabase/renewal_migration_999_drop_season1.sql`: 시즌2 API 전환·백업 검증 후 실행할 시즌1 DB 삭제 SQL
- `docs/RENEWAL-UI-SYSTEM.md`, `docs/RENEWAL-VISUAL-UX-AUDIT.md`: 공통 UI와 시각 승인 기준
- `tests/regression-suite.md`: 자동·수동 회귀 범위

## 날짜가 고정된 증거 문서

- `docs/PDB-1-PLAYTEST-2026-07-17.md`: 1차 플레이테스트 기록. 최신 밸런스로 최종 재테스트 필요
- `production/performance/performance-profile-2026-07-17.md`: 당시 성능 측정. 배포 전 전체 재측정 필요
- `production/security/security-audit-2026-07-17.md`: 당시 보안 점검. 서버 구현 후 재점검 필요

## 역사 문서

- 시즌1 전용 README와 과거 인수인계는 시즌2 저장소 정리 과정에서 삭제했다.
- `RESEARCH-REPORT-MOBILE-IDLE-RPG-2026.md`: 시장 조사 자료. 계정 레벨 사례는 시즌2에 채택하지 않았다.
- `.zcode/plans/plan-sess_04f6ec5e-8eaf-4280-a26d-766136dad837.md`: 계정 레벨 제거 작업의 착수 전 계획. 완료 결과는 최신 밸런스 문서가 우선한다.

## 2026-07-18 현재 확정값

- 밸런스 `2026.07.18-random-loot-1`, 상태 스키마 v2
- 계정 레벨·계정 EXP 없음
- 각 등급 F~SSS에 8개 전투 유형 균등 배치, 0성 도달 단계 `3/5/8/10/11/18/24/33/40`
- 동일 종족 4장은 3장 시너지 유지. 표시 전투력에 공격속도·치명타·패시브·회복·약화 반영
- 30일 진행: 하위 16단계 미완주, 중위 28일 완주, 상위 13일 완주
- 강화 파괴 시 원본 유지, 강화 단계·카드 EXP 0 초기화
- 미니게임별 일일 5,000P
- 월드보스 KST 17·18·19·20시, 회차별 30분 전투·30분 결과, 성공 최대 10,000P
- 모험런·빠른 전투·월드보스 결과에서 상점 아이템·카드팩 교환권 랜덤 추가 드롭
- 강화 성공 FX 4단계 총 3.12초, 강화 구간별 강도 차등
- 자동 테스트 29묶음 통과. 직전 밸런스 30일 성장 시뮬레이션 통과
