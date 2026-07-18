# PDB-8 시즌1 계정 이관 명세

## 확정 정책

- 시즌1 원본 테이블은 읽기 전용으로 보존한다.
- 시즌2에는 계정 식별·로그인 정보만 이관한다.
- 카드, 도감, 편성, 대표 카드, 강화, 카드 EXP, 아이템, 모험, 미니게임, 월드보스, 랭킹 전투력은 전부 초기화한다.
- 시즌1 보유 카드 합계가 0인 비스트리머 계정은 시즌2에 이관하지 않는다.
- `gacha_soop_bridge_keys`에 SOOP ID가 등록된 스트리머 계정은 카드가 0장이어도 이관하고 게임 상태만 초기화한다. `active` 값과 무관하다.
- 시즌2 시작 포인트는 계정당 5,000P다.
- 시즌1 최종 top50은 시작 포인트에 순위 보상을 더한다.

## 랭커 보상

| 시즌1 최종 순위 | 추가 보상 | 시즌2 시작 합계 |
|---|---:|---:|
| 1~10위 | 30,000P | 35,000P |
| 11~20위 | 20,000P | 25,000P |
| 21~30위 | 15,000P | 20,000P |
| 31~40위 | 10,000P | 15,000P |
| 41~50위 | 5,000P | 10,000P |
| 그 외 | 0P | 5,000P |

top50 전체 추가 지급량은 800,000P다.

## 계정 필드 매핑

| 시즌1 | 시즌2 | 규칙 |
|---|---|---|
| `gacha_users.id` | `legacy_user_id`, 시즌2 `id` | 기존 UUID 유지 |
| `nickname` | `nickname` | 공백 제거 후 1~40자 검증 |
| `login_key_hash` | `login_key_hash` | SHA-256 64자리 그대로 유지 |
| `soop_id` | `soop_id` | null 허용, non-null 고유 |
| `created_at` | `legacy_created_at` | 기존 가입 시각 유지 |
| top50 `rank` | `season1_final_rank` | 1~50 고유 |
| 브릿지 키 SOOP ID 일치 | `is_streamer` | 카드 0장 계정 보존 기준 |

`last_ip`, 시즌1 포인트, 출석, 연속 출석, 시즌1 점수는 이관하지 않는다.

## 초기화 범위

- `gacha_s2_player_cards`: 0행
- 포인트: 5,000P + 랭커 보상
- 행동력: 최대치
- 진행 스테이지: 0
- 카드·도감·시리얼: 없음
- 편성·대표 카드: 없음
- 강화·카드 EXP: 없음
- 보유 아이템·버프: 0
- 모험·빠른 전투·미니게임·월드보스 기록: 0
- 전투력과 시즌2 랭킹: 0, 미집계

## 스트리머 판별

시즌1 `gacha_soop_bridge_keys.soop_id = gacha_users.soop_id`면 스트리머다.

- 브릿지 키가 비활성이어도 계정은 유지한다.
- 브릿지 키 해시는 재발급하지 않고 기존 원장을 보존한다.
- 카드 0장 스트리머도 5,000P와 해당 랭커 보상을 받는다.
- SOOP ID가 브릿지 원장에 없고 카드 합계도 0이면 시즌2에서 제외한다.

시즌1 분해·합성 RPC는 각 카드 수량을 최소 1장 남긴다. 따라서 `gacha_collection` 보유 합계 0은 카드팩을 한 번도 열지 않은 계정 판별값으로 사용할 수 있다.

## 입력 자료

전체 export:

```json
{
  "users": [],
  "collection": [],
  "cardSerials": [],
  "memberRewards": [],
  "bridgeKeys": []
}
```

최종 순위 스냅샷은 별도 `rows` 50개 JSON을 사용한다. 로컬 백업:

`C:\Users\silve\OneDrive\Desktop\card-gacha\tmp\season1-final-top50-snapshot.json`

## 로컬 dry-run

```powershell
npm.cmd run dry-run:season1-import -- `
  --input C:\secure\season1-export.json `
  --ranking-snapshot C:\Users\silve\OneDrive\Desktop\card-gacha\tmp\season1-final-top50-snapshot.json `
  --sample 10 `
  --report C:\secure\season1-dry-run.json
```

거부 조건:

- 중복 사용자 ID, 로그인 해시, SOOP ID
- orphan collection
- 음수·비정수 카드 수량
- top50 50행 불일치, 중복·누락 순위, 누락 사용자
- 생성된 시즌2 상태 스키마 검증 실패

## SQL 실행 절차

파일: `supabase/renewal_migration_001_accounts_reset.sql`

1. 파일 리뷰와 백업 완료.
2. 운영자가 SQL Editor에서 migration 실행.
3. `select public.gacha_s2_preview_season1_import();` 실행.
4. `sourceUsers`, `retainedUsers`, `excludedNoCardNonStreamerUsers`, `retainedStreamersWithoutCards`, top50 검증값, 포인트 총액 확인.
5. 승인한 원본·유지 계정 수를 넣어 `gacha_s2_import_season1_accounts` 실행.
6. `gacha_s2_player_cards`가 0행인지 확인.
7. 시즌1 원본 행 수·합계가 변하지 않았는지 재확인.

import는 advisory lock, batch UUID 멱등성, 예상 계정 수 일치, 빈 시즌2 대상 테이블 조건을 모두 통과해야 실행된다. 실패하면 트랜잭션 전체가 롤백된다.

## 현재 상태

- 로컬 분석기와 합성 테스트 완료.
- 실제 top50 스냅샷 50행, 순위 1~50, 보상 총액 800,000P 검증 완료.
- 1차 migration SQL 작성 완료. 운영 Supabase에는 미실행.
- 전체 시즌1 export 기준 실제 유지·제외 계정 수 dry-run은 아직 필요하다.
