# Regression Suite Manifest

> Last Updated: 2026-07-18
> Total registered test files: 28

## 실행

```powershell
npm.cmd run test:renewal
```

## 필수 회귀 묶음

| 시스템 | 테스트 | 보호 범위 |
|---|---|---|
| 설정 | `renewal-config.test.js` | 확률 합계·밸런스 버전 |
| 상태 | `renewal-state-schema.test.js` | v0·v1→v2 변환·계정 레벨 제거·손상 거부 |
| 서비스 | `renewal-game-service.test.js` | 저장·clock·RNG 경계 |
| API 계약 | `renewal-service-contract.test.js` | 멱등성·revision·응답 |
| 요청 UX | `renewal-request-coordinator.test.js` | 연타 잠금·재시도·오류 상태 |
| 보안 | `renewal-security.test.js` | 비밀 패턴·닉네임 이스케이프 |
| 이관 | `renewal-season1-import.test.js` | 5,000P·top50 차등 보상·카드 0장 비스트리머 제외·브릿지 보존 |
| DB migration | `renewal-database-migration.test.js` | 시즌1 원본 무변경·계정/브릿지 이관·RLS·빈 카드 인벤토리 |
| DB 카탈로그 | `renewal-database-catalog.test.js` | 212장 결정적 seed·밸런스 해시·RLS·카드 FK·생성 파일 최신성 |
| 명령 기반 | `renewal-command-foundation.test.js` | 서버 스냅샷·멱등 재생·revision 행 잠금·보유/EX 편성·service role 제한 |
| 팩·강화 RPC | `renewal-pack-enhancement-rpc.test.js` | 서버 난수·확률표·원자 경제 처리·재료 보호·파괴 초기화·감사 로그 |
| 모험·미니게임 RPC | `renewal-adventure-minigame-rpc.test.js` | 서버 전투 검증 경계·런 제한·원자 보상·서버 보드·입력 로그 재검산·service role 제한 |
| 시즌1 DB 삭제 | `renewal-season1-cleanup.test.js` | 이중 확인문구·수량/해시 검증·삭제 allowlist·CASCADE 금지 |
| 저장소 정리 | `renewal-repository-hygiene.test.js` | 시즌2 루트·카드 자산 완전 일치·시즌1 앱 경로 제거 |
| 전투 | `renewal-battle.test.js` | 역할 반영 전투력·3/4/5장 종족 시너지·광역/보스 적용·전투 이벤트 |
| 모험 | `renewal-adventure.test.js` | 4시간당 3회·실패 종료·보상 |
| 랜덤 추가 드롭 | `renewal-bonus-loot.test.js` | 모험 단계별·월드보스 성공/실패·아이템·팩 티켓 |
| 밸런스 | `renewal-balance.test.js` | 0성 등급별 도달 구간·S9/SS5 완주·D/E/F9 최종 미완주·지역 난도 단조성 |
| 방치 보상 | `renewal-rewards.test.js` | 24시간·EXP·행동력 |
| 강화 | `renewal-enhancement.test.js` | 재료·확률·파괴·9성 |
| 도감 | `renewal-collection.test.js` | 전투 50%·방치 30% |
| 상점 | `renewal-shop.test.js` | 카드팩·보급품·버프 |
| 콘텐츠 | `renewal-content.test.js` | 212장·삭제 8장 제거·신규 10장·SSS 고정·F~SS 수량·등급별 8유형 균등 분포 |
| 미니게임 | `renewal-minigames.test.js` | 보드·점수·일일 상한 |
| 월드보스 | `renewal-worldboss.test.js` | 30분 전투·30분 결과·3회·성공/실패 보상 |
| 랭킹 | `renewal-rankings.test.js` | 전투력 순위·백분위 |
| 카드 UI | `renewal-card-visual.test.js` | 등급·성급·프레임 |
| FX | `renewal-fx.test.js` | 강화 성공 4단계·3.12초·구간별 강도, 팩·고등급 수동 공개 |

## 브라우저 필수 경로

- 7개 메뉴 진입과 현재 hash 새로고침.
- 편성, 보상, 구매, 강화, 미니게임, 월드보스 작업 연타 방지.
- 로딩·오프라인·세션 만료·충돌·서버 오류 화면.
- 도감 이탈 후 대형 DOM 회수.
- 깨진 이미지와 가로 넘침 0건.

## Known Gaps

- 실제 Supabase 네트워크·RLS·RPC 통합 테스트는 운영 migration 실행 전 staging에서 추가.
- 저사양 Android 영상 디코딩과 실제 동시 접속 부하는 배포 후보에서 측정.

## Quarantined Tests

없음.
