# Calm MonstarZ 카드뽑기 (Gacha)

캄몬스타즈 크루 카드 수집 가챠 웹앱. 정적 프론트 + Vercel 서버리스(`api/`) + Supabase.

## 구조

```
card-gacha/
├─ index.html            프론트 SPA (로그인/상점/개봉연출/도감)
├─ api/                  Vercel 서버리스 함수 (CommonJS)
│   ├─ register.js       POST 닉네임 가입 → KEY 발급
│   ├─ login.js          POST KEY 로그인
│   ├─ attend.js         POST 출석 (하루 1회 +200P, Asia/Seoul 기준)
│   ├─ open-pack.js      POST 카드팩 구매·개봉 (서버 뽑기)
│   ├─ collection.js     GET  보유 도감
│   ├─ cards.js          GET  전체 카드 목록(등급 포함)
│   └─ announcements.js  GET  최근 UR+ 레어드랍 공지
├─ lib/                  서버 공용 (env 파서 / supabase REST / 가챠 로직 / http)
├─ data/cards.json       빌드 산출물 (87장, id·member·file·rarity)
├─ assets/
│   ├─ cards/            ASCII 리네임된 카드 이미지 87장
│   └─ card-back.png     카드 뒷면 로고 (Calm MonstarZ)
├─ scripts/
│   ├─ build-cards.js    cards.json 생성 + 이미지 복사 (시드 고정)
│   └─ dev-server.js     로컬 개발 서버 (포트 3300, 의존성 0)
├─ supabase/migration.sql  DB 마이그레이션
└─ .env.local           Supabase 키 (Git 커밋 금지)
```

## 1. 카드 데이터 빌드

원본 87장(`C:\Users\silve\OneDrive\Desktop\card`)을 ASCII 파일명으로 복사하고 `data/cards.json`을 생성한다. 시드 고정이라 재실행해도 결과 동일.

```
node scripts/build-cards.js
```

- 등급 규칙: 김윤환 5장 = FUR / 소주양1·지두두1 = FUR / 남자코치 7명 = C·U·R / 나머지 여성 = 13등급 가중(각 등급 최소 1장 보장).
- 카드 뒷면: `C:\Users\silve\OneDrive\Desktop\card-back.png`(고화질본)이 있으면 그걸, 없으면 monstarznew 파비콘을 `assets/card-back.png`로 복사. 나중에 고화질 파일만 저 경로에 두고 다시 빌드하면 교체됨.

## 2. Supabase 마이그레이션

1. Supabase 콘솔 → SQL Editor.
2. `supabase/migration.sql` 전체를 붙여넣고 Run.
3. 테이블 3개(`gacha_users`, `gacha_collection`, `gacha_announcements`) 생성 + RLS 활성화.

> 정책(policy)을 만들지 않으므로 anon 접근은 전면 차단되고, 서버리스 함수의 service_role 키만 통과한다.

## 3. 로컬 실행

```
node scripts/dev-server.js
```

- http://localhost:3300 접속.
- `.env.local`을 자동 파싱(dotenv 불필요). Supabase 값이 채워져 있어야 api가 동작.
- `vercel dev` 없이 정적 + api를 동시 서빙. 별도 npm install 불필요(Node 18+).

## 4. Vercel 배포

1. 이 폴더를 **새 Vercel 프로젝트**로 임포트(기존 monstarznew와 별개).
2. 프레임워크 프리셋: **Other** (빌드 명령 없음, 정적 + `api/` 자동 인식).
3. Project Settings → Environment Variables 에 아래 4개 등록:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY` (또는 `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`)
   - `SUPABASE_SERVICE_ROLE_KEY` (또는 `SUPABASE_SECRET_KEY`)
   - (선택) 위 값들의 대체 키
4. 배포 전 로컬에서 `node scripts/build-cards.js`를 돌려 `data/cards.json`과 `assets/`를 커밋했는지 확인.
5. Deploy.

> `.env.local`과 `node_modules`는 `.gitignore`에 포함되어 커밋되지 않는다. 키는 프론트 코드에 하드코딩하지 않고 서버리스에서만 사용한다.

## 게임 규칙 요약

| 항목 | 값 |
|---|---|
| 가입 보너스 | 1000P |
| 출석 | 하루 1회 +200P (Asia/Seoul, 서버 검증) |
| 일반팩 | 100P · 3장 |
| 고급팩 | 300P · 4장 · 마지막 R 이상 확정 |
| 프리미엄팩 | 800P · 5장 · 마지막 SR 이상 확정 |

- 뽑기: 등급 롤 → 해당 등급 카드풀 균등 랜덤(등급 비면 한 단계 아래 폴백). 전부 서버 처리(암호학적 난수).
- 중복 허용(도감에 보유 수량 표시).
- UR 이상 뽑으면 전체 공지 티커에 노출(최근 24시간·최신 20건).
- MUR/FUR은 개봉 시 별도 2단계 스페셜 연출(직접 탭해서 오픈).

## 인증 방식

- 가입: 닉네임 입력 → 서버가 32자 hex KEY 발급 → 화면 안내 + 복사 + localStorage 저장.
- 로그인: KEY 입력만. 닉네임 중복 허용(KEY가 유일 식별자).
