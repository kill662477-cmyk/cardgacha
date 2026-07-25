# 길드 구현 인수인계 (작업 중단 지점)

> 최종 갱신: 2026-07-25 · 브랜치 `feature/guild` · 기획서 `docs/PDB-16-GUILD-CONTENT.md`

## 1. 지금 상태 한 줄

**M1~M4 전 단계 코드 완료 + 검증 완료.** `main` 미접촉, **DB 미적용**, 라이브 영향 0.
남은 일은 라이브 반영(7절)과 실제 레이드 시간대 스모크 확인뿐이다.

## 2. 절대 지킬 것

| 규칙 | 이유 |
|---|---|
| **`main` 에 푸시 금지** | `main` 푸시 = Vercel 즉시 라이브 배포. 작업은 `feature/guild` 에서만 |
| **DB 마이그레이션 적용 금지** | "전 단계 완료 후 라이브 반영" 지시. 지금은 파일로만 존재 |
| 검증은 **트랜잭션 롤백**으로 | psql·DB직통·CLI토큰 전부 없음. MCP `execute_sql` 에 `begin; ... rollback;` 한 문자열로 보내면 됨(검증됨) |
| 공유 모듈 수정 시 `node scripts/build-edge-shared.mjs` | 안 하면 stale 검사 테스트가 실패 |

## 3. 이미 밟은 지뢰 (다시 밟지 말 것)

1. **길드 명령은 revision 을 반드시 +1 해야 한다.**
   `gacha_s2_command_audit` 에 `CHECK (committed_revision = expected_revision + 1)` 이 있다.
   "길드는 player_states 를 안 바꾸니 revision 안 올림"으로 짰다가 **모든 길드 명령이 100% 실패**했다.
   현재 `gacha_s2_guild_command_ok` 가 일괄 처리한다. 회귀 테스트로 고정해 둠.

2. **해산 시 `guild_members` 행을 삭제해야 한다.**
   `guild_members(user_id)` 가 유일 인덱스라, 행을 남기면 잔여 길드원이 다른 길드에 영영 못 들어간다.

3. **정원은 절대 줄이면 안 된다.**
   `gacha_s2_guild_refresh_level` 이 `greatest(신규, 기존, 현재인원)` 으로 계산한다.

4. **스냅샷 수정 시 필드 손실 확인 필수.**
   `gacha_s2_get_player_snapshot` 은 전체 재정의 방식이라 복사 실수 시 필드가 날아간다.
   검증법: 재정의 전 키 목록을 temp 테이블에 저장 → 재정의 → 차집합 비교(실제로 이렇게 검증했음).

## 4. 완료 내역

### M1 — 길드 뼈대
- 마이그레이션 `20260725000092~96`: 스키마 5테이블 / 조회 RPC / 생성·해산·설정 / 신청·취소·승인 / 탈퇴·추방·역할
- `service-contract.js` 명령 9종, `server-command-router.js` 매핑·인자변환
- edge `game-command/index.ts` 에 `guildState` kind, `supabase-game-service.js` 에 `getGuildState`
- UI: `index.html` 길드 화면, `guild-controller.js`, `main.css`, 네비 탭(랭킹↔모험 사이)

### M2 — 공헌도·레벨·버프
- `20260725000097`: `guild_levels`(10단계) / `guild_contributions` / **감사 로그 트리거로 GP 적립** / `guild_buff()`
- `20260725000098`: 스냅샷에 `guildBuff` 추가
- `config.js` 의 `GUILD_RULES`, `guildLevelFor()`
- `collection.js` 의 `applyGuildBuff()` — **서버 `verifiedContext` 와 클라 `currentCombatBonuses` 가 같은 함수를 써야 전투 재현 검증이 안 깨진다**
- UI: 레벨·누적 GP·버프 요약, 기여도 정렬(역할/낮은순/높은순)

### 검증 완료 (트랜잭션 롤백, 잔여물 0)
- 스키마 제약 7종, RPC 실행 8종(멱등·revision·권한·중복 차단 등)
- GP 7종(트리거 적립/비대상 무시/일일상한 200/레벨업·정원확장/버프값/무소속 0/정원 축소 방지)
- 스냅샷: 기존 30필드 보존 + `guildBuff` 1개만 추가
- 전체 자동 테스트 41개 통과 (`node --test tests/*.test.js`)

### M3 — 주간 공동목표 (`20260725000099`)
- 진행도를 저장하지 않고 `guild_contributions` 에서 집계. 개인 상한 8% 적용에 개인 내역이
  필요한데 이미 일별로 쌓이기 때문이다.
- `actions` 컬럼 추가: GP 는 하루 상한(200)에 걸리면 횟수를 역산할 수 없어 수행 횟수를 따로 센다.
  GP 가 상한으로 0 이어도 목표 진행에는 기여한다.
- 주간 리셋은 cron 없이 `week_start_kst` 키로 자연히 갈린다.
- 검증: 주 시작 월요일, 목표 인원 비례, 1인 999회 → 상한까지만, 혼자선 달성 불가,
  전원 상한 충족 시 달성, 지난주 기여 미집계.

### M4 — 길드 레이드 (`20260725000100~101`)
- 수·토 21:00 KST, 전투 30분 + 결과 30분. 월드보스 시뮬레이션 재사용.
- **HP = 활동 길드원 수 × 21,000,000** (참여자 수 아님). 참여자 비례로 두면 몇 명이 오든
  난이도가 같아져 다수 참여 유인이 사라진다. 활동 = 최근 7일 공헌 기록.
- 보상 명단은 회차 시작 시점 소속 전원을 미리 생성 → 처치 후 가입해 보상만 받는 것 차단,
  종료 후 미참여자 표시 가능.
- 성공 시 전원 50,000P / 실패 시 참여자만 15,000P.
- 검증: 슬롯 5케이스, HP 활동인원 기준, 유령 회원 미반영, 명단 전원, 멱등, 비슬롯 미생성.

## 5. 남은 확인 사항

**시간 의존 경로는 실제 레이드 시간에 스모크가 필요하다.**
`gacha_s2_attack_guild_raid` / `gacha_s2_claim_guild_raid_reward` 는 내부에서 `now()` 를 쓰므로
트랜잭션 테스트로 시각을 주입할 수 없었다. 슬롯 계산·회차 생성·HP 산정·명단 생성은 검증했으나,
공격 3회 제한과 보상 분기(성공 전원 / 실패 참여자만)는 **수·토 21:00 KST 에 실제로 한 번 돌려봐야** 한다.

주간 목표의 `claimGuildWeeklyReward` 도 같은 이유로 실제 달성 상황에서 한 번 확인이 필요하다.

## 6. 참고 값

- 테스트 계정: 스트리머 `2d16a861-7f6a-4dcb-9b8d-58c6c1289fea`(Mstz_손실바) / 일반 `0001b704-e478-449e-9597-f04272e70674`
- Supabase project ref: `rljvzultuyiudhjjfotg`
- 로컬 확인: `npm run dev` → `http://127.0.0.1:3300` (로컬도 remote 모드라 로그인 필요. UI 만 볼 거면 DOM 에 더미 주입해서 확인했음)

## 7. 최종 라이브 반영 절차 (모든 단계 완료 후)

1. `feature/guild` 전체 테스트 통과 확인
2. 마이그레이션 순서대로 적용: `...092 → 093 → 094 → 095 → 096 → 097 → 098` (+M3/M4 추가분)
3. edge 재배포: `npx supabase functions deploy game-command --project-ref rljvzultuyiudhjjfotg --no-verify-jwt`
   (MCP 인라인 배포 금지 — cards.json 40KB 로 이전에 프로덕션을 한 번 죽였음)
4. `main` 병합 → Vercel 자동 배포
5. 실제 계정으로 길드 생성·가입·승인 스모크 확인
