# PDB-4 게임 서비스 경계

## 목적

화면과 컨트롤러가 브라우저 저장소, 시스템 시각과 시스템 난수에 직접 의존하지 않게 한다. 현재 로컬 프로토타입은 그대로 플레이할 수 있고, PDB-5 이후 서버 서비스로 교체할 때 화면과 FX를 다시 작성하지 않는 구조를 기준으로 한다.

## 계층

```text
app / controllers
        |
        v
game service interface
        |
        v
local-game-service
   |             |
storage       clock / RNG
```

- `app.js`와 화면 컨트롤러는 게임 서비스의 명명된 작업만 호출한다.
- `local-game-service.js`는 현재 상태 스냅숏과 로컬 저장을 소유한다.
- `storage.js`만 `localStorage`를 사용한다.
- `runtime.js`만 시스템 `Date.now()`와 `Math.random()`을 노출한다.
- 전투, 추첨, 강화 같은 도메인 함수는 전달받은 시각과 난수로 계산한다.

## 서비스 인터페이스

```text
loadSnapshot
resetSnapshot
persistSnapshot
updateFormation
claimAdventureRewards
purchasePack
enhanceCard
startMinigame
finishMinigame
attackWorldBoss
claimWorldBossReward
getPowerRanking
now
random
```

`persistSnapshot`은 아직 이름 없는 로컬 상태 변경을 지원하는 과도기용 작업이다. PDB-5에서 포인트, 보상, 추첨, 강화와 전투를 각각 서버 명령으로 확정한 뒤 제거 대상을 다시 판단한다.

## 저장 규칙

- 성공한 저장만 `revision`을 1 증가시킨다.
- 저장 검증 실패 시 메모리 상태와 저장 상태의 revision을 바꾸지 않는다.
- 서비스의 clock과 RNG는 테스트에서 고정 구현으로 교체할 수 있다.
- 화면은 저장 성공 이전 결과를 서버 확정 결과로 간주하지 않는다. 현재 로컬 어댑터는 동기 저장이므로 즉시 확정된다.

## 검증

- `tests/renewal-game-service.test.js`에서 모든 서비스 메서드 존재 여부와 revision 증가를 확인한다.
- 고정 clock과 고정 RNG로 동일 입력의 재현성을 확인한다.
- UI 파일에서 `localStorage`, `Date.now()`와 `Math.random()` 직접 호출이 없는지 소스 감사를 수행한다.
- 전체 리뉴얼 테스트 16개 묶음을 통과한다.
- 로컬 브라우저에서 상점 구매, 포인트 반영과 현재 메뉴 hash 복원을 확인한다.

## PDB-5 연결점

다음 단계에서는 각 명령의 요청·응답, 멱등성 키, 서버 시각, 서버 시드, 버전 충돌과 오류 코드를 정의한다. 서버 어댑터는 이 인터페이스를 기반으로 추가하며, 클라이언트가 계산한 보상·추첨·강화 결과를 신뢰하지 않는다.
