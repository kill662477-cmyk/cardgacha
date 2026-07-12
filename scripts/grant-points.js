// 전 계정 포인트 추가 지급 (현재 포인트 + N). 실행: node scripts/grant-points.js 200 --confirm
const { rpc } = require('../lib/supabase');

async function run() {
  const amount = parseInt(process.argv[2], 10);
  if (!amount || !process.argv.includes('--confirm')) {
    console.log('사용법: node scripts/grant-points.js <지급액> --confirm');
    process.exit(1);
  }
  const rows = await rpc('gacha_grant_all_points', { p_amount: amount });
  const updated = rows?.[0]?.updated_count;
  if (!Number.isInteger(updated)) throw new Error('지급 결과를 확인할 수 없습니다');
  console.log(`완료: ${updated}명에게 각 +${amount}P 지급`);
}

run().catch(e => { console.error('실패:', e.message || e); process.exit(1); });
