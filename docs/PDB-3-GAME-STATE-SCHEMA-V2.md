# PDB-3 게임 상태 스키마 v2

> 상태: 통과
> 스키마 버전: `2`
> 실행 가능한 단일 원본: `src/renewal/state-schema.js`
> 저장 구현: `src/renewal/storage.js`

## 목적

로컬 프로토타입의 저장 상태를 서버 이전 가능한 계약으로 고정한다. 계정 레벨과 계정 EXP는 시즌2 성장 구조에서 제거하며, 전투 성장은 카드 등급·강화·종족 시너지·도감 보너스로만 계산한다. Supabase 테이블, RPC, RLS, 계정 연결과 운영 데이터 이관은 아직 만들지 않는다.

## 공통 메타

| 필드 | 형식 | 규칙 |
|---|---|---|
| `schemaVersion` | integer | 반드시 `2` |
| `revision` | integer | 0 이상. 저장 성공 때 1 증가 |

`revision`은 낙관적 잠금과 버전 충돌 응답에 사용한다. 저장 검증이나 브라우저 저장이 실패하면 증가하지 않는다.

## 서버 권위 상태

- 프로필: `nickname`, `representativeCardId`
- 재화: `points`, `actionEnergy`, `maxActionEnergy`
- 시간: `lastEnergyAt`, `lastRewardAt`, `activeBuffs`
- 카드: `cardProgress`, `cardCopies`, `cardLocks`, `collectionRecords`, `formation`, `formationPresets`, `activeFormationPresetId`
- 인벤토리: `supportItems`
- 모험: `clearedStage`, `pendingPoints`, `quickBattle`, `adventureRuns`, `adventureRun`, `exMilestoneClaims`
- 통계: `shopTransactions`, `enhancementAttempts`
- 콘텐츠: `miniGames`, 최근 검증 로그 `miniGameRuns`, `worldBoss`
- 랭킹: 서버 계산 결과 `powerRanking`
- 계약: `schemaVersion`, `revision`

`accountLevel`, `accountExp`는 허용 필드가 아니다. 향후에도 별도 승인 없이 복원하지 않는다.

## 클라이언트 캐시·환경설정

- `currentStage`: 진행 중 런에서 다시 계산 가능한 화면 캐시
- `autoBattle`: 현재 기기의 자동 진행 환경설정
- `soundEnabled`: 현재 기기의 음향 환경설정

이 세 필드는 시즌1 이관 대사와 서버 보상 판정에서 제외한다.

## 핵심 불변식

- 포인트, 재료, 아이템, 카드 수량과 경험치는 음수 불가
- 행동력은 기본 최대치의 2배 이하
- 카드 강화는 `0~9성`, 경험치는 현재 단계 요구량 이하
- 강화 파괴 판정은 원본 카드를 유지하고 해당 카드의 강화 단계·EXP만 `0`으로 초기화
- 편성과 프리셋은 최대 5장, 동일 카드 ID 중복 불가
- 모험 런은 항상 1단계에서 시작하고 첫 런 시작부터 4시간 동안 최대 3회
- 월드보스 도전은 회차당 최대 3회, 보상 단계는 `-1~최종 단계`
- 미니게임은 `memory`, `sumTen` 각각 하루 최대 `5,000P`, 합계 최대 `10,000P`
- 미니게임 검증 로그는 최근 20개 이하
- 랭킹 순위는 전체 인원보다 클 수 없음
- 날짜 키는 `YYYY-MM-DD`
- 존재하지 않는 카드 ID와 선언되지 않은 최상위 필드 거부

## 버전 변환

### v0 무버전 저장값

- 기존 유효 값 유지
- 폐기 필드 제거와 누락 중첩 필드 보충
- `schemaVersion: 2`, `revision: 0` 적용 후 v2 전체 검증

### v1 저장값

- `accountLevel`, `accountExp` 삭제
- 모험·빠른 전투 초기화권과 게임별 미니게임 기록 등 누락 필드 보충
- 나머지 진행, 카드, 포인트와 설정 유지
- 변환 완료 후 `schemaVersion: 2`로 승격하고 전체 검증

### 미래 버전

현재 클라이언트보다 높은 `schemaVersion`은 자동 하향 변환하지 않고 거부한다.

## 저장 정책

1. 저장 후보 스냅숏 생성
2. `revision + 1`
3. 전체 상태 검증
4. 브라우저 저장 성공
5. 메모리 상태의 버전과 revision 갱신

검증 실패나 저장 실패 시 기존 저장값과 메모리 revision을 유지한다.

## 테스트 증거

`tests/renewal-state-schema.test.js`가 기본 v2, v0·v1 변환, 계정 레벨 필드 제거, 미래 버전 거부, 음수·중복·잘못된 강화·미등록 필드 거부와 revision 보존을 검증한다.

```powershell
node tests/renewal-state-schema.test.js
npm.cmd run test:renewal
```

## 다음 단계

운영 서버 명령 구현 시 이 v2 필드명과 의미를 유지한다. DB 스키마와 운영 이관은 사용자 승인 전 실행하지 않는다.
