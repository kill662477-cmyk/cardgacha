// 기존 유저 랭킹 점수 백필 스크립트
// 도감의 모든 카드 가치를 합산하여 ranking_score 초기값을 세팅합니다.
// node scripts/sync-scores.js
const { REST, headers, sbFetch } = require('../lib/supabase');
const { cardById, DISMANTLE_REFUND, MEMBER_REWARDS } = require('../lib/gacha');

async function getMemberRewardsScore(userId) {
  try {
    const rows = await sbFetch(`${REST}/gacha_member_rewards?user_id=eq.${userId}`, {
      headers: headers()
    });
    return rows.reduce((score, row) => score + (MEMBER_REWARDS[row.member] || 0), 0);
  } catch (e) {
    return 0; // 테이블이 없거나 에러면 0
  }
}

async function run() {
  console.log('백필 시작...');
  const users = await sbFetch(`${REST}/gacha_users?select=id,nickname`, { headers: headers() });
  console.log(`대상 유저: ${users.length}명`);

  for (const user of users) {
    let score = 0;
    const collections = await sbFetch(`${REST}/gacha_collection?user_id=eq.${user.id}`, { headers: headers() });
    
    // 1. 보유 중인 모든 카드 가치 합산 (중복 포함)
    for (const c of collections) {
      const cardInfo = cardById(c.card_id);
      if (cardInfo && c.count > 0) {
        const val = DISMANTLE_REFUND[cardInfo.rarity] || 0;
        score += val * c.count; 
      }
    }

    // 2. 수령한 멤버 완성 보상 점수 합산
    score += await getMemberRewardsScore(user.id);

    // 업데이트
    await sbFetch(`${REST}/gacha_users?id=eq.${user.id}`, {
      method: 'PATCH',
      headers: headers({ Prefer: 'return=minimal' }),
      body: JSON.stringify({ ranking_score: score })
    });
    console.log(`- ${user.nickname}: ${score}점 업데이트 완료`);
  }
  console.log('완료되었습니다.');
}

run().catch(console.error);
