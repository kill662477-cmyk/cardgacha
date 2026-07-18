# PDB-13 모험·미니게임 서버 RPC

## 범위

- SQL: `supabase/renewal_migration_005_adventure_and_minigames.sql`
- 계약: `src/renewal/service-contract.js`
- 테스트: `tests/renewal-adventure-minigame-rpc.test.js`
- 상태: 로컬 작성·정적 검증 완료. 운영 Supabase 미실행

## 판정 경계

모험 공식은 기존 공유 JavaScript 전투 엔진을 단일 원본으로 유지한다. 인증된 Edge/service 계층이 서버 스냅샷과 활성 밸런스로 전투를 재현한 뒤 service role 전용 RPC에 클리어 수와 SHA-256 검증 해시를 전달한다. 브라우저 명령에는 클리어 수, 해시, 보상과 전투 결과가 없다.

미니게임은 DB가 보드와 제한시간을 생성한다. 완료 RPC는 입력 로그를 서버 보드에 다시 적용해 점수와 완료 여부를 계산한다. 클라이언트 입력 해시는 받지 않고 DB가 보관용 SHA-256 해시를 만든다.

## 데이터

- `gacha_s2_adventure_runs`: 모드, 서버 시드, 5인 편성, 검증 결과, 정산 보상·추가 드롭 감사
- `gacha_s2_minigame_daily`: KST 날짜·게임별 포인트, 플레이 수, 최고점
- `gacha_s2_minigame_runs`: 서버 보드, 제한시간, 입력 로그, 검증 점수와 보상
- 사용자마다 진행 중 모험 1개, 진행 중 미니게임 1개만 허용
- 세 테이블 모두 RLS 활성화, 공개 직접 접근 차단

## 명령

| 명령 | 브라우저 payload | 서버 처리 |
|---|---|---|
| `startAdventureRun` | 없음 | service 계층 전투 검증, 4시간 3회, 편성 스냅샷, 실행 생성 |
| `finishAdventureRun` | `runId` | 저장된 결과로 포인트·카드 EXP·추가 드롭·EX 원자 정산 |
| `claimQuickBattle` | 없음 | 행동력 20, KST 하루 3회, 모험 횟수 공유, 즉시 정산 |
| `startMinigame` | `game`, `difficulty` | 일일 한도·행동력 확인, 서버 보드 생성 |
| `finishMinigame` | `runId`, `inputLog`, `score` | 로그 재생, 점수 대조, 게임별 하루 5,000P 상한 지급 |

모든 명령은 멱등성 재생을 revision 충돌보다 먼저 검사한다. 성공 시 revision을 정확히 1 증가시키고 감사 로그를 남긴다.

## 재접속

`gacha_s2_get_player_snapshot`은 진행 중 모험의 실행 ID·검증 결과와 진행 중 미니게임의 서버 보드·제한시간·시작/만료 시각을 반환한다. 만료 뒤 15초가 지난 미니게임은 제외한다. 클라이언트 상태 검증기도 이 서버 실행 형태만 허용한다.

## 부정행위 방어와 한계

- 카드 짝맞추기는 입력 순서, 중복 선택, 제한시간과 UI의 성공 `320ms`·실패 `650ms` 해제 시간을 검증한다.
- 캄몬사과게임은 서버 보드의 남은 타일로 모든 사각 선택을 다시 계산한다.
- 자동 스크립트가 합법적인 입력 로그를 만드는 행위까지 완전히 증명할 수는 없다. 공개 전 요청 빈도, 비정상 완료시간과 반복 패턴 탐지가 필요하다.
- SQL은 로컬 정적 검증만 완료했다. 실제 PostgreSQL 문법, RLS와 동시성은 preview Supabase에서 별도 검증한다.

## 다음

후속 `PDB-14`에서 월드보스 회차·공동 HP·개인 시도·결과시간 보상 수령을 서버 권위로 구현했다. 상세 기준은 `docs/PDB-14-WORLD-BOSS-RPC.md`를 따른다.
