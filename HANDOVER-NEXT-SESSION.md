# 인수인계 — 다음 세션용 (2026-07-11, 토큰 소진으로 중단)

## 프로젝트
Calm MonstarZ 카드가챠. `Desktop\card-gacha`. 정적 SPA(index.html) + Vercel serverless(api/) + Supabase(monstarznew 프로젝트 재사용, .env.local 있음). 로컬: `node scripts/dev-server.js` 포트 3300. migration.sql 실행됨(DB 살아있음).

## 완료된 것
1. **본편 완성 + 실기검증 통과**: 가입(닉네임→key발급)→로그인→출석(+200P)→팩3종(일반100/고급300/프리미엄800, 보장 R+/SR+)→개봉연출(MUR/FUR는 별도 스포트라이트→뒷면 수동 클릭 플립)→도감(등급필터)→UR+ 상단 티커 공지(30초 폴링)
2. **Codex 작업 반영됨**: assets/frames/*.svg 13종(등급프레임), assets/packs/*.png 3종, assets/fx/{mur,fur}-intro.{webm,mp4}, assets/card-back.jpg. 등급 재배치됨(FUR 5장 분산, cards.json 총 87장) — **cards.json 재생성 절대 금지(유저 데이터 축적 중)**
3. **HANDOVER-CODEX.md** 있음(과거 인수인계, 배포 옵션 설명 포함)

## 진행 중이던 것 (중단 시점)
보완사항 구현을 opus 백그라운드 에이전트에 위임한 상태였음 — **완료 여부 미확인. 다음 세션에서 먼저 git/파일 상태 훑고 아래 목록 중 뭐가 이미 구현됐는지 확인부터 해라.**

### 위임했던 작업 목록 (확률공시 페이지는 사용자가 제외 지시)
A. **도감 신비주의(최우선)**: 미보유 카드 = 사진 실루엣 아니라 **card-back.jpg 흑백+어둡게**. 사진 노출 금지. 멤버명·등급뱃지는 표시.
B. **카드 상세 모달**: 보유카드 클릭 → 대형뷰(프레임 포함) + 마우스 틸트 홀로. 수량/등급/첫획득일. 미보유는 안 열림.
C. **사운드**: WebAudio 합성(외부파일 0) — 플립스냅/팩찌직/SR+아르페지오/FUR라이저. 기본 켜짐, 헤더 음소거 토글(localStorage).
D. **분해**: 환급 C5 U8 R15 RR25 RRR40 AR60 CHR80 HR100 SR130 SAR170 UR220 MUR300 FUR400. 최소1장 보존, 초과분만. `api/dismantle` POST {key,cardId,count} + mode:"all" 일괄. 서버 검증. UI: 모달 분해버튼 + 도감 상단 일괄분해(미리보기→확인).
E. **멤버 완성 보상**: 멤버 전카드 보유시 1회 500P. `api/claim-reward` {key,member}, 서버가 도감 대조+gacha_member_rewards로 중복 방지. 도감에 "보상 받기" 뱃지.
F. **티커 실시간화**: supabase-js CDN + `api/public-config`(url+anon key 반환, monstarznew api/supabase-config.js 패턴) + Realtime INSERT 구독. 실패시 기존 폴링 폴백.
G. **출석 개편**: gacha_users.streak 컬럼. 어제 출석=streak+1 아니면 1. 보상 기본200, streak 7의 배수날 400, 가입 7일내 +100. UI에 "연속 N일".
H. **OG태그+파비콘**: og:image=card-back.jpg(배포 도메인 placeholder), 파비콘은 monstarznew favicon 복사 가능(`Desktop\MONSTARZNEW_PROJECT_REPOS_20260617-104902\monstarznew\assets\monstarz-favicon-192.png`).

### migration2.sql (에이전트가 supabase/migration2.sql 생성 예정이었음 — 있으면 사용자에게 실행시켜라)
```sql
alter table gacha_users add column if not exists streak int not null default 0;
create table if not exists gacha_member_rewards (
  user_id uuid references gacha_users(id) on delete cascade,
  member text not null,
  rewarded_at timestamptz default now(),
  primary key (user_id, member)
);
alter table gacha_member_rewards enable row level security;
create policy "anon read announcements" on gacha_announcements for select to anon using (true);
alter publication supabase_realtime add table gacha_announcements;
```
migration2 실행 전에도 기존 기능은 전부 정상 동작해야 함(graceful 폴백 요구했음).

## 확정 결정사항 (재논의 금지)
- 배포 = **Vercel** (GitHub Pages는 serverless 불가로 탈락, HANDOVER-CODEX.md 참조). 아직 배포 안 함 — README 절차대로 임포트+환경변수 4개.
- 등급 13단계 C~FUR. 남자코치 7명(변현제 김민철 사테 박준오 박수범 지동원 배성흠)=하위등급, 김윤환=FUR (단 사용자가 코덱스에서 등급 재배치했으므로 현 cards.json이 정본).
- 브랜드 표기 "Calm MonstarZ" / "캄몬스타즈"만.
- 크루 로스터 21명(2026-07-11 확정): 김윤환 김민철 변현제 사테 박준오 박수범 지동원 배성흠 남덕선 토마토 지두두 햇살 찌킹 치리 주하랑 소주양 임조이 비타밍 먼진 아리송이 낭니.
- 확률 상향 금지(희소성 유지). 확률공시 페이지 만들지 않기(사용자 지시).
- 디자인: 다크 신스웨이브 단일 테마, Pretendard+JetBrains Mono, radius 12px, em-dash 화면텍스트 금지, reduced-motion 폴백, 모바일 대응.

## 다음 세션 첫 행동
1. `card-gacha` 파일 상태 확인 (api/dismantle.js, api/claim-reward.js, api/public-config.js, supabase/migration2.sql 존재 여부 = 에이전트 완료 여부 판단)
2. 미완이면 위 A~H 스펙대로 이어서 구현 (역할분담: 기획=메인, 코드=opus 에이전트)
3. 완료돼 있으면: 사용자에게 migration2.sql 실행 요청 → dev-server 3300으로 브라우저 전체 검증(신비주의 도감, 모달, 분해, streak, realtime) → Vercel 배포 안내
