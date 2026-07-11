# Calm MonstarZ 카드뽑기 — Codex 인수인계서

작성: 2026-07-11, Fable5 기획. 대상: Codex (비주얼 에셋 제작 + 연출 고도화 담당).

---

## 0. 프로젝트 현황 (완료된 것)

- 위치: `C:\Users\silve\OneDrive\Desktop\card-gacha`
- 정적 SPA(`index.html`) + Vercel serverless(`api/` 7개: register, login, attend, open-pack, collection, cards, announcements) + Supabase(테이블 3개: gacha_users, gacha_collection, gacha_announcements — 마이그레이션 실행 완료)
- 카드 87장(`data/cards.json`, `assets/cards/`), 등급 13단계: C, U, R, RR, RRR, AR, CHR, HR, SR, SAR, UR, MUR, FUR
- 전체 플로우 실기 검증 완료: 가입(key발급) → 출석(+200P) → 팩 3종 구매 → 개봉 연출 → 도감 → UR+ 티커
- 로컬 실행: `node scripts/dev-server.js` → http://localhost:3300
- 디자인: 다크 신스웨이브, Pretendard + JetBrains Mono, 시안 액센트, TCG 5:7 카드, radius 12px
- 브랜드 표기: **"Calm MonstarZ"** (한글 병기 "캄몬스타즈") — 다른 변형 금지

### 절대 건드리지 말 것
- `api/`의 뽑기 확률·포인트 차감·출석 검증 로직 (서버 신뢰 구조)
- `data/cards.json`의 등급 배정 (시드 고정, `scripts/build-cards.js` 재실행 금지 — 이미 유저 도감에 card_id가 쌓이는 중이므로 id/등급 변경은 파괴적)
- `.env.local` (Supabase 키)
- 원본 사진 폴더 `Desktop\card` (읽기 전용)

---

## 과제 1. 등급별 카드 프레임 13종

### 목표
현재 카드는 사진 + CSS 글로우/보더만 있음. 등급별 전용 프레임 이미지를 오버레이해 TCG 실물 카드 느낌으로.

### 에셋 스펙
- 파일: `assets/frames/{rarity}.png` (13개: c.png, u.png, r.png, rr.png, rrr.png, ar.png, chr.png, hr.png, sr.png, sar.png, ur.png, mur.png, fur.png)
- 크기: 1024×1434 (5:7), PNG 알파. **중앙부는 투명** — 사진이 프레임 안쪽으로 보이는 구조. 프레임 안쪽 개구부는 대략 상하좌우 7~8% 여백.
- 하단 밴드: 멤버 이름 + 등급 라벨 들어갈 공간(높이 약 12%)을 프레임 디자인에 포함 (텍스트는 코드가 렌더, 프레임은 배경 밴드만)
- 등급별 재질 위계 (아래로 갈수록 화려):
  - C / U: 무광 그레이 메탈, 최소 장식
  - R / RR / RRR: 블루 스틸, 모서리 리벳/라인 장식 점증
  - AR / CHR: 실버 크롬 + 시안 라인 발광
  - HR / SR: 골드 프레임, 코너 엠블럼
  - SAR / UR: 플래티넘 + 마젠타 인레이, 세공 화려
  - MUR: 다크 홀로(흑요석 + 무지개 미세 반사), 위압감
  - FUR: 풀 레인보우 홀로포일, 프리즘 굴절, 최상위 티가 나야 함
- 스타일 통일: 신스웨이브 블루 무드와 충돌 금지. 13종이 한 세트로 보여야 함(동일 구도/두께, 재질만 상승).

### 제작 방법
AI 이미지 생성 사용. 검증된 파이프라인 둘 중 택1:
1. Gemini `gemini-2.5-flash-image`(Nano Banana) — `GEMINI_API_KEY`, SLAY THE MONSTARZ 프로젝트에서 캐릭터 22종 생성 실적. 참고 도구: `Desktop\slay-the-monstarz` 쪽 `tools/gen_images.py` (stdlib REST, 다중 ref 입력, 재시도)
2. AetherForge API — 검증 도구 `CALMSV\tools\aether_assets.py`

프롬프트 팁: "trading card frame, transparent center window, {재질 서술}, symmetrical ornament, dark synthwave, PNG" + 13종 일관성 위해 첫 장(C) 확정 후 그것을 style ref로 나머지 12종 생성. 투명 중앙은 생성 후 후처리(중앙 사각영역 알파 컷)가 더 안정적일 수 있음 — ffmpeg/PIL로 컷.

### 코드 통합
- 카드 렌더 함수(도감 + 개봉 연출 + 상세)에 rarity→프레임 이미지 오버레이 레이어 추가 (`position:absolute; inset:0`, 사진 위, 텍스트 아래 z-order)
- 프레임 로드 실패 시 현재 CSS 보더 폴백 유지
- 도감 그리드는 축소 렌더라 프레임 PNG lazy-load + `loading="lazy"` 필수 (87장 × 프레임)

---

## 과제 2. 상점 팩 이미지 3종

### 목표
상점 벤토 셀의 팩 3종을 실물 부스터팩 일러스트로 교체.

### 에셋 스펙
- 파일: `assets/packs/normal.png`, `assets/packs/rare.png`, `assets/packs/premium.png` (내부 팩 id는 코드 확인 — open-pack API가 받는 packId와 매칭)
- 세로 부스터팩 형태(호일 파우치), 3:4 ~ 2:3 비율, 1024px+
- 공통: MONSTARZ 로고(파란 눈알 몬스터 + 노란 별, `assets/card-back.png` 참조) 전면 중앙, 상단 크림프(팩 접합부) 표현
- 일반팩: 블루/실버 호일, 담백
- 고급팩: 골드 호일 + 블루, "R+" 느낌의 고급감
- 프리미엄팩: 홀로 프리즘 호일, 레인보우 반사, 최상급
- 배경 투명(PNG 알파) — 벤토 셀 다크 배경 위에 얹힘

### 코드 통합
- 상점 벤토 각 셀에 팩 이미지 배치 (프리미엄 히어로 셀은 크게)
- 개봉 연출 도입부: 팩 이미지가 등장 → 찢어지는/터지는 트랜지션 후 카드 등장 (CSS clip-path 또는 두 조각 분리 애니메이션). reduced-motion 시 즉시 스킵.

---

## 과제 3. MUR/FUR 등장 애니메이션 영상

### 목표
현재 MUR/FUR 특별 연출(스포트라이트+오라)은 CSS/JS 코드 구성. 이걸 사전 렌더 영상으로 교체해 임팩트 극대화.

### 권장 제작: Remotion (코드 기반 영상, React)
- 이유: 등급 색상 파라미터화 가능, 재현성, AI 영상보다 통제 쉬움. 사용자 PC에 Remotion 작업 경험 있음(Windows/OneDrive 주의사항은 remotion 스킬 참조 — OneDrive 경로 렌더링 이슈 있으니 렌더 출력은 로컬 임시폴더로 뽑고 복사).
- 연출안 (각 2.5~3초, 1920×1080, 30fps):
  - **MUR**: 암전 → 마젠타/바이올렛 번개 균열 → 포털 개방 → 카메라 줌인, 마지막 프레임은 어두운 배경(뒷면 카드 리스트로 자연 전환되게 끝을 어둡게)
  - **FUR**: 암전 → 레인보우 홀로 성운 소용돌이 → 프리즘 광선 폭발 → 화이트아웃 직전에 컷, 끝 프레임 어둡게
  - 로고/텍스트 삽입 금지 (등급 스포일러 없이 색으로만 예고)
- 포맷: WebM(VP9) 우선 + MP4(H.264) 폴백. 투명 알파 불필요 — 풀스크린 오버레이 영상이므로 불투명으로 제작(용량↓, Safari 호환↑). 목표 용량 각 3MB 이하.
- 파일: `assets/fx/mur-intro.webm`, `assets/fx/fur-intro.webm` (+ .mp4 폴백)

### 코드 통합
- 특별 연출 진입 시: `<video muted playsinline autoplay>` 풀스크린 오버레이 재생 → `ended` 이벤트에서 뒷면 카드 리스트 표시
- 영상 로드 실패/미지원 시 현재 CSS 연출 폴백 그대로 유지 (지우지 말 것)
- reduced-motion: 영상 스킵하고 바로 카드 리스트
- 영상 preload: 팩 구매 버튼 클릭 시점에 prefetch (개봉 시점 버퍼링 방지)

---

## 과제 4. 추가 보완점 (우선순위순)

1. **카드 상세 모달**: 도감 카드 클릭 → 대형 카드 뷰 + 마우스 틸트 홀로 이펙트(개봉 연출의 틸트 재사용). 보유 수량, 등급, 획득일 표시.
2. **사운드**: 팩 개봉/카드 플립/FUR 등장 SFX. 기본 mute, 헤더에 토글. 파일 `assets/sfx/`. 모바일 자동재생 정책 주의(유저 제스처 후에만).
3. **중복 카드 분해**: 중복분 포인트 환급(등급별 환급표: C 5P ~ FUR 400P 수준, 뽑기 가격 대비 기대값 붕괴 안 되게 보수적으로). API 추가 필요(`api/dismantle`) — 서버 검증 필수.
4. **도감 완성 보상**: 멤버별 컴플리트(해당 멤버 전 카드) 시 보너스 포인트 1회 지급. 서버 검증.
5. **티커 실시간화**: 30초 폴링 → Supabase Realtime 구독(anon key로 gacha_announcements SELECT만 RLS 허용 정책 추가 필요 — 공지는 공개 정보라 안전).
6. **확률 공시 페이지**: 팩별 등급 확률표 + 등급별 카드 목록 정적 페이지. 팬 신뢰용.
7. **OG 메타태그 + 파비콘**: 카톡/디코 공유 시 로고 카드 프리뷰.
8. **포인트 이코노미 검토(기획)**: 현재 일 200P = 이틀에 일반팩 1개. 체감 느림. 후보: 연속 출석 보너스(7일차 ×2), 첫 가입 주간 부스트. 확률 상향은 금지(희소성 유지).

---

## 배포 관련 (사용자 질문 답변 겸)

**GitHub Pages 단독 배포 불가.** 이유: GitHub Pages는 정적 호스팅만 지원 — `api/` serverless 함수가 안 돌아감. 가입/로그인/뽑기/출석 전부 서버 검증 구조라 API 없으면 앱이 동작 안 함.

옵션:
- **A. Vercel (권장)**: 현 구조 그대로, Hobby 무료 티어로 충분(정적+serverless). README 절차대로 임포트 + 환경변수 4개.
- **B. GitHub Pages + Supabase Edge Functions**: 정적은 Pages, API 7개를 Supabase Edge Functions(Deno)로 포팅. 가능하지만 포팅 공수 + CORS 설정 + 무료티어 호출량 제한 고려. Vercel 대비 이득 없음.
- **C. GitHub Pages + anon 직접 접근**: RLS만으로 방어 — 뽑기 확률/포인트를 클라이언트가 계산하게 되어 조작 가능. **탈락.**

결론: Vercel로 배포. GitHub 레포는 소스 관리용으로 쓰고 Vercel이 해당 레포를 바라보게 연결하면 push 자동배포까지 됨.
