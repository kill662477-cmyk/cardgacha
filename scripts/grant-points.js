// 전 계정 포인트 추가 지급 (현재 포인트 + N). 실행: node scripts/grant-points.js 200 --confirm
const { REST, headers, rpc, sbFetch } = require('../lib/supabase');

async function grantOne(userId, amount) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const users = await sbFetch(`${REST}/gacha_users?id=eq.${userId}&select=id,points`, { headers: headers() });
    const user = users?.[0];
    if (!user) throw new Error(`대상 계정을 찾을 수 없습니다: ${userId}`);
    const rows = await sbFetch(`${REST}/gacha_users?id=eq.${user.id}&points=eq.${user.points}`, {
      method: 'PATCH',
      headers: headers({ Prefer: 'return=representation' }),
      body: JSON.stringify({ points: user.points + amount }),
    });
    if (rows?.[0]) return;
  }
  throw new Error(`포인트 갱신 충돌이 반복되었습니다: ${userId}`);
}

async function grantWithCompareAndSet(amount) {
  const users = await sbFetch(`${REST}/gacha_users?select=id`, { headers: headers() });
  let cursor = 0;
  const workers = Array.from({ length: Math.min(6, users.length) }, async () => {
    while (cursor < users.length) {
      const index = cursor++;
      await grantOne(users[index].id, amount);
    }
  });
  await Promise.all(workers);
  return users.length;
}

async function run() {
  const amount = parseInt(process.argv[2], 10);
  if (!amount || !process.argv.includes('--confirm')) {
    console.log('사용법: node scripts/grant-points.js <지급액> --confirm');
    process.exit(1);
  }
  let updated;
  try {
    const rows = await rpc('gacha_grant_all_points', { p_amount: amount });
    updated = rows?.[0]?.updated_count;
    if (!Number.isInteger(updated)) throw new Error('지급 결과를 확인할 수 없습니다');
  } catch (error) {
    if (!/UPDATE requires a WHERE clause/.test(error.message || '')) throw error;
    console.log('일괄 지급 RPC가 차단되어 충돌 안전 폴백으로 처리합니다.');
    updated = await grantWithCompareAndSet(amount);
  }
  console.log(`완료: ${updated}명에게 각 +${amount}P 지급`);
}

run().catch(e => { console.error('실패:', e.message || e); process.exit(1); });
