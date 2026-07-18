# PDB-5 서버 판정·API 계약 v1

## 경계

- 클라이언트는 행동 의도와 선택값만 전송한다.
- 포인트, 카드, 보상, 강화 결과, 전투 피해와 랭킹은 서버가 현재 상태로 다시 계산한다.
- 성공 응답의 `snapshot`과 `result`만 저장·FX 재생의 근거로 사용한다.
- Supabase 함수, RPC, 테이블과 RLS는 승인된 PDB-9 범위에서 로컬 작성하며 운영 실행은 별도 승인 뒤 진행한다.

## 전송

- 예정 경로: 인증된 Supabase Edge Function 또는 RPC 단일 진입점
- 요청 방식: `POST`
- 본문: JSON 명령 봉투
- 인증: Supabase access token 필수
- 클라이언트 제한시간 권장값: 10초
- 재시도: 같은 `idempotencyKey`와 같은 본문을 그대로 재전송

## 명령 봉투

```json
{
  "contractVersion": 1,
  "commandId": "purchase-019f...",
  "idempotencyKey": "purchase-019f...",
  "type": "purchasePack",
  "expectedRevision": 41,
  "clientSentAt": 1784246400000,
  "payload": {}
}
```

- `commandId`와 `idempotencyKey`는 같아야 한다.
- 키는 계정 범위에서 유일하며 최소 24시간 보존한다. 포인트·카드 지급 명령은 시즌 종료까지 보존을 권장한다.
- `expectedRevision`은 클라이언트가 마지막으로 받은 서버 상태 revision이다.
- `clientSentAt`은 진단용이다. 보상·쿨다운 판정에는 사용하지 않는다.
- 계약에 없는 필드는 거부한다.

## 명령별 최소 입력

| 명령 | payload | 서버 판정 |
|---|---|---|
| `updateFormation` | `formation: cardId[1..5]` | 보유·중복·EX 제외·편성 제한 |
| `claimAdventureRewards` | `mode: offline/quick/run` | 경과 시각·행동력·런 결과·보상 |
| `startAdventureRun` | 없음 | 서버 편성·밸런스로 전투 재현, 4시간 3회, 실행 생성 |
| `finishAdventureRun` | `runId` | 저장된 검증 결과로 포인트·EXP·드롭·EX 정산 |
| `claimQuickBattle` | 없음 | 행동력·당일 횟수·모험 런 횟수, 서버 전투와 즉시 정산 |
| `purchasePack` | `productId`, `quantity: 1/10`, `race` | 가격·확률·시드·포인트·카드 지급 |
| `enhanceCard` | `cardId`, `targetEnhancement`, `materialCardIds[1..3]`, `boosterId` | 경험치 게이트·재료·확률·파괴·비용 |
| `startMinigame` | `game: memory/sumTen`, 메모리 `difficulty` | 일일 상한·행동력·runId·서버 보드·제한시간 |
| `finishMinigame` | `runId`, `inputLog`, `score` | 서버 보드에 입력 로그 재적용·시간·점수·보상 |
| `attackWorldBoss` | `eventId` | 회차·횟수·편성 스냅숏·피해·공동 HP |
| `claimWorldBossReward` | `eventId` | 달성 피해·공동 성공 여부·중복 수령·보상 단계 |

클라이언트가 계산한 `reward`, `damage`, `drawResults`, `success`, `pointsAfter`는 입력으로 받지 않는다.

## 성공 응답

```json
{
  "contractVersion": 1,
  "ok": true,
  "commandId": "purchase-019f...",
  "idempotencyKey": "purchase-019f...",
  "revision": 42,
  "serverTime": 1784246400123,
  "serverSeed": 127391204,
  "snapshot": {},
  "result": {}
}
```

- 트랜잭션 커밋 뒤 반환한다.
- `revision`은 성공한 명령마다 정확히 1 증가한다.
- `snapshot.revision`과 응답 `revision`은 같아야 한다.
- `serverSeed`는 추첨·강화·전투·미니게임 검증 추적용이다. 비밀 난수 원본은 노출하지 않는다.
- 재전송이면 새 추첨 없이 최초 성공 응답을 그대로 반환한다.

## 오류 응답

| 코드 | HTTP 권장 | 재시도 | 처리 |
|---|---:|---|---|
| `VALIDATION_FAILED` | 400 | 아니오 | 잘못된 클라이언트 요청 차단 |
| `AUTH_REQUIRED` | 401 | 재인증 후 | 로그인 모달 |
| `FORBIDDEN` | 403 | 아니오 | 권한 없음 표시 |
| `VERSION_CONFLICT` | 409 | 사용자 확인 후 | `latestSnapshot`으로 새로고침 |
| `IDEMPOTENCY_KEY_REUSED` | 409 | 아니오 | 새 키로 자동 재전송 금지 |
| `COMMAND_REJECTED` | 422 | 아니오 | 포인트·재료·횟수 등 게임 규칙 안내 |
| `RATE_LIMITED` | 429 | 예 | `Retry-After` 뒤 같은 키 재전송 |
| `OFFLINE` | 503 | 예 | 연결 복구 뒤 같은 키 재전송 |
| `INTERNAL_ERROR` | 500 | 예 | 제한 횟수 내 같은 키 재전송 |

버전 충돌 응답에는 최신 `revision`과 `latestSnapshot`을 포함한다. 일반 오류는 상태를 변경하지 않는다.

## 권한

- 모든 명령은 인증 사용자 본인의 상태만 변경한다.
- SOOP 브릿지 키, 운영자 키와 service role key는 브라우저에 전달하지 않는다.
- 후원 지급은 게임 명령 API가 아니라 검증된 브릿지 이벤트의 서버 전용 경로에서 처리한다.
- 랭킹 읽기는 공개 가능하나 닉네임·전투력·순위 외 계정 식별자와 상태 원문을 반환하지 않는다.
- 월드보스 공동 HP 갱신은 트랜잭션 또는 원자 RPC로 처리한다.

## 트랜잭션 단위

- 카드팩: 포인트 차감 + 추첨 기록 + 카드 지급 + revision
- 강화: 재료·아이템·포인트 차감 + 결과 + 카드 상태 + revision
- 모험 시작: 실행 횟수 차감 + 편성 스냅샷 + 검증 결과 저장 + revision
- 모험 정산: 실행 소비 + 포인트·카드 EXP·드롭·EX + revision
- 빠른 전투: 행동력·당일/런 횟수 차감 + 즉시 정산 + revision
- 미니게임 완료: run 소비 + 입력 검증 + 일일 상한 + 포인트 + revision
- 월드보스 공격: 시도 차감 + 개인 피해 + 공동 HP + revision
- 보상 수령: 달성 검증 + 중복 수령 잠금 + 지급 + revision

중간 실패 시 전부 롤백한다.

## 구현 기준

- 계약 코드: `src/renewal/service-contract.js`
- 로컬 서버 대역: `src/renewal/in-memory-command-gateway.js`
- 테스트: `tests/renewal-service-contract.test.js`
- 검증 항목: 요청·응답 스키마, 동일 키 재전송, 키 재사용 공격, stale revision 충돌, 서버 시각·시드
