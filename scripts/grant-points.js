// 전 계정 포인트 추가 지급 (현재 포인트 + N). 실행: node scripts/grant-points.js 200 --confirm
const { REST, headers, sbFetch } = require('../lib/supabase');

async function run() {
  const amount = parseInt(process.argv[2], 10);
  if (!amount || !process.argv.includes('--confirm')) {
    console.log('사용법: node scripts/grant-points.js <지급액> --confirm');
    process.exit(1);
  }
  const users = await sbFetch(`${REST}/gacha_users?select=id,nickname,points`, { headers: headers() });
  console.log(`대상 ${users.length}명, 각 +${amount}P`);
  let ok = 0;
  for (const u of users) {
    await sbFetch(`${REST}/gacha_users?id=eq.${u.id}`, {
      method: 'PATCH',
      headers: headers({ Prefer: 'return=minimal' }),
      body: JSON.stringify({ points: u.points + amount }),
    });
    ok++;
  }
  console.log(`완료: ${ok}/${users.length}명 지급`);
}

run().catch(e => { console.error('실패:', e.message || e); process.exit(1); });
