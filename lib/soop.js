// SOOP 계정 식별용 공용 파서.
//
// stationinfo 응답에는 로그인ID 필드가 없지만, profile_image URL 경로에 로그인ID가
// 두 번(디렉토리명·파일명) 포함된다:
//   https://profile.img.sooplive.com/LOGO/si/silver0love/silver0love.jpg
//   패턴: /LOGO/{로그인ID 앞2글자}/{로그인ID}/{로그인ID}.{확장자}
//
// 실증: silver0love, jyoung2 (Vercel 로그). DB의 soop_id 는 전부 이 로그인ID 기준.

// profile_image URL 에서 SOOP 로그인ID 를 추출한다.
// 디렉토리명·파일명·앞2글자 프리픽스를 교차확인해 견고하게 검증하고,
// 어느 하나라도 어긋나면 null 을 돌려준다(폴백 금지 → 중복계정 재발 방지).
function extractSoopLoginId(profileImageUrl) {
  if (!profileImageUrl || typeof profileImageUrl !== 'string') return null;

  let url;
  try {
    url = new URL(profileImageUrl.trim());
  } catch (e) {
    return null;
  }

  // sooplive.com 계열 호스트만 신뢰한다(다른 도메인 → null).
  if (!/(^|\.)sooplive\.com$/i.test(url.hostname)) return null;

  // /LOGO/{prefix}/{dir}/{file}.{ext}
  const m = url.pathname.match(/\/LOGO\/([^/]+)\/([^/]+)\/([^/]+)\.[a-zA-Z0-9]+$/);
  if (!m) return null;

  const prefix = m[1];
  const dir = m[2];
  const file = m[3];

  // 디렉토리명 == 파일명(확장자 제외) 교차확인
  if (dir !== file) return null;
  // 앞2글자 프리픽스 == 로그인ID 앞2글자 교차확인
  if (prefix.toLowerCase() !== dir.slice(0, 2).toLowerCase()) return null;

  return dir;
}

module.exports = { extractSoopLoginId };
