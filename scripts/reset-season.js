// 기존 계정들의 도감, 랭킹을 초기화하고 3000포인트를 지급하는 스크립트
const { REST, headers, sbFetch } = require('../lib/supabase');

async function run() {
  console.log('초기화 작업 시작...');

  // 1. 컬렉션 삭제
  console.log('도감(gacha_collection) 초기화 중...');
  await sbFetch(`${REST}/gacha_collection?card_id=not.is.null`, {
    method: 'DELETE',
    headers: headers(),
  });

  // 2. 멤버 보상 수령 내역 삭제
  console.log('멤버 보상 수령 내역(gacha_member_rewards) 초기화 중...');
  await sbFetch(`${REST}/gacha_member_rewards?member=not.is.null`, {
    method: 'DELETE',
    headers: headers(),
  });

  // 3. 기존 공지사항 삭제 (선택사항이지만 깔끔한 시작을 위해)
  console.log('공지사항 티커(gacha_announcements) 초기화 중...');
  await sbFetch(`${REST}/gacha_announcements?id=not.is.null`, {
    method: 'DELETE',
    headers: headers(),
  });

  // 4. 유저 점수 0, 포인트 3000 으로 세팅
  console.log('기존 유저 포인트 3000 지급 및 랭킹 점수 0점 초기화 중...');
  // 조건 없는 PATCH는 허용 안될 수 있으므로, ID가 null이 아닌 모든 레코드 업데이트
  await sbFetch(`${REST}/gacha_users?id=not.is.null`, {
    method: 'PATCH',
    headers: headers({ Prefer: 'return=minimal' }),
    body: JSON.stringify({ ranking_score: 0, points: 3000 }),
  });

  console.log('모든 초기화가 성공적으로 완료되었습니다!');
}

run().catch(e => {
  console.error('초기화 실패:', e.message);
});
