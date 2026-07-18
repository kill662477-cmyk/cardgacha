# PDB-14 월드보스 서버 RPC

## 범위

- SQL: `supabase/renewal_migration_006_world_boss.sql`
- 계약: `src/renewal/service-contract.js`
- 테스트: `tests/renewal-worldboss-rpc.test.js`
- 상태: 로컬 작성·정적 검증 완료. 운영 Supabase 미실행

## 확정 규칙

- KST 매일 `17:00`, `18:00`, `19:00`, `20:00` 시작
- 회차당 전투 30분, 결과·보상 수령 30분
- 개인 최대 3회, 전투 1회 60초, 편성 카드마다 EXP 25
- 공동 HP 50억
- 서버 기본 기여 초당 `2,766,667`, 30분 총 `4,980,000,600`
- 전체 참가자 피해가 약 2천만 이상 추가되어야 성공
- 개인 누적 피해 단계와 공동 성공/실패를 함께 반영, 최고 10,000P
- 결과 구간에서 회차당 한 번만 수령, 추가 아이템·카드팩 교환권 추첨

## 데이터

- `gacha_s2_world_boss_events`: 회차 시간, 밸런스 버전, 공동 HP, 참가자 피해, 서버 기여율, 격파 시각
- `gacha_s2_world_boss_players`: 개인 시도·최고/누적/최근 피해, 수령 단계·포인트·추가 드롭
- `gacha_s2_world_boss_attempts`: 명령 ID, 시도 번호, 편성 스냅샷, 검증 피해·해시·카드 EXP 감사

같은 사용자·회차의 시도 번호와 명령 ID는 중복될 수 없다. 개인·시도 테이블은 공개 읽기와 쓰기를 모두 차단한다.

## RPC

| 함수 | 역할 |
|---|---|
| `gacha_s2_ensure_world_boss_schedule` | 현재·다음 KST 회차를 활성 밸런스로 생성 |
| `gacha_s2_tick_world_boss_events` | 서버 기본 기여를 공동 HP에 반영 |
| `gacha_s2_get_world_boss_status` | 공동 HP, 결과 상태, 개인 기록·순위, TOP 10 반환 |
| `gacha_s2_attack_world_boss` | 시도 차감, 공동 HP·개인 피해·카드 EXP·revision 원자 반영 |
| `gacha_s2_claim_world_boss_reward` | 결과시간·참가·중복을 검증하고 포인트·추가 드롭 원자 지급 |

브라우저 `attackWorldBoss`는 `eventId`만 보낸다. Edge/service 계층이 서버 스냅샷과 공유 전투 엔진으로 피해를 재현해 내부 RPC에 피해와 SHA-256 검증 해시를 전달한다. 브라우저 `claimWorldBossReward`도 `eventId`만 보내며 성공 여부, 보상 단계와 포인트는 DB가 계산한다.

## Realtime

`gacha_s2_world_boss_events`만 인증 사용자 읽기를 허용하고 `supabase_realtime` publication에 조건부 등록한다. 개인 계정 ID와 공격 감사는 노출하지 않는다.

운영 스케줄러는 `gacha_s2_tick_world_boss_events()`를 5~10초 간격으로 호출한다. 공격·상태 조회·보상 수령도 HP를 즉시 동기화하므로 누락된 tick이 보상 판정을 바꾸지는 않는다.

## 보안·운영 주의

- 공격·보상 명령은 사용자 상태 행을 먼저 잠그고 멱등성 재생, revision, 회차 순으로 검증한다.
- 공동 HP는 이벤트 행 단일 원자 UPDATE로 감소한다. 1,500명·개인 3회 기준 staging burst 부하 테스트가 필요하다.
- `gacha_s2_get_world_boss_status`의 `p_user_id`는 Edge에서 인증 토큰의 사용자 ID로 고정한다.
- SQL은 실제 PostgreSQL에서 실행하지 않았다. preview에서 문법, RLS, publication 권한, 동시 공격과 회차 경계를 검증해야 한다.

## 다음

PDB-15에서 `supabase-game-service`와 Edge 명령 라우터를 구현해 로컬 UI를 실제 RPC에 연결한다.
