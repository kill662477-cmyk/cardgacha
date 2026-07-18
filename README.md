# 카드가챠 시즌2

SOOP 스트리머와 팬이 카드를 뽑고 성장시켜 모험, 월드보스와 미니게임에 사용하는 웹 게임이다.

## 현재 상태

- 로컬 게임 플레이 구현 완료
- 카드 212장, F~SSS 전투 카드와 EX 전시 카드
- 상점, 강화, 도감, 전투력 랭킹, 모험, 월드보스, 미니게임 구현
- 게임 상태 스키마 v2와 서버 명령 계약 구현
- 시즌2 계정 이관 1차 Supabase migration 작성, 운영 미실행
- 서버 권위 카드 212장·밸런스 스냅샷 2차 migration 작성, 운영 미실행
- 멱등성·revision 명령 기반과 전투 편성 RPC 3차 migration 작성, 운영 미실행
- 카드팩 구매·강화 원자 RPC 4차 migration 작성, 운영 미실행
- 모험·빠른 전투·미니게임 검증 RPC 5차 migration 작성, 운영 미실행
- 월드보스 회차·공동 HP·공격·보상 RPC 6차 migration 작성, 운영 미실행
- push·배포 전 로컬 검증 단계

## 실행

```powershell
npm.cmd run dev
```

브라우저: `http://127.0.0.1:3300`

## 검증

```powershell
npm.cmd test
npm.cmd run simulate:renewal-balance
```

## 주요 경로

- `index.html`: 시즌2 진입점
- `src/renewal/`: 게임 로직과 화면 제어
- `styles/renewal/`: 시즌2 UI
- `data/renewal-cards.json`: 전체 카드 카탈로그
- `assets/renewal/`: 시즌2 전용 UI·배경·팩·FX 자산
- `assets/cards/`: 카드 사진 212개
- `supabase/renewal_migration_001_accounts_reset.sql`: 시즌1 계정·브릿지 선별 이관과 시즌2 초기 상태
- `supabase/renewal_migration_002_catalog_and_balance.sql`: 서버 권위 카드 카탈로그와 밸런스 스냅샷
- `supabase/renewal_migration_003_command_foundation.sql`: 서버 스냅샷·영구 도감·명령 감사·전투 편성 RPC
- `supabase/renewal_migration_004_pack_and_enhancement.sql`: 서버 난수 카드팩 구매·강화 원자 RPC
- `supabase/renewal_migration_005_adventure_and_minigames.sql`: 모험 정산·빠른 전투·서버 보드 미니게임 RPC
- `supabase/renewal_migration_006_world_boss.sql`: KST 월드보스 회차·공동 HP·개인 시도·결과 보상 RPC
- `supabase/renewal_migration_999_drop_season1.sql`: 시즌2 전환 검증 후 시즌1 DB 제거
- `HANDOVER-CLAUDE-CODE-RENEWAL.md`: 최신 인수인계

## 운영 주의

- 운영 Supabase migration은 preview 계정 수 확인 전 실행 금지.
- 시즌1 원본은 이관·API 전환·백업 검증 때까지만 읽기 전용 유지. 이후 `999`로 삭제.
- 사용자 지시 전 push·배포 금지.
