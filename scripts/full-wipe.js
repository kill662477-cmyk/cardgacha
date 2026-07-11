// 전체 초기화: 모든 계정·도감·보상내역·공지 완전 삭제 (되돌릴 수 없음)
// 실행: node scripts/full-wipe.js --confirm
const { REST, headers, sbFetch } = require('../lib/supabase');

async function count(table) {
  const idcol = table === 'gacha_collection' ? 'card_id' : table === 'gacha_member_rewards' ? 'member' : 'id';
  const rows = await sbFetch(`${REST}/${table}?select=${idcol}`, { headers: headers() });
  return Array.isArray(rows) ? rows.length : '?';
}

async function wipe(table, filter) {
  await sbFetch(`${REST}/${table}?${filter}`, { method: 'DELETE', headers: headers() });
  console.log(`  ${table} 삭제 완료`);
}

async function run() {
  if (!process.argv.includes('--confirm')) {
    console.log('전체 삭제 스크립트. 계정 포함 모든 데이터가 사라집니다.');
    console.log('실행하려면: node scripts/full-wipe.js --confirm');
    process.exit(1);
  }
  console.log('삭제 전 행 수:');
  for (const t of ['gacha_users', 'gacha_collection', 'gacha_member_rewards', 'gacha_announcements']) {
    console.log(`  ${t}: ${await count(t)}`);
  }
  console.log('전체 초기화 시작...');
  await wipe('gacha_collection', 'card_id=not.is.null');
  await wipe('gacha_member_rewards', 'member=not.is.null');
  await wipe('gacha_announcements', 'id=not.is.null');
  await wipe('gacha_users', 'id=not.is.null');
  console.log('삭제 후 행 수:');
  for (const t of ['gacha_users', 'gacha_collection', 'gacha_member_rewards', 'gacha_announcements']) {
    console.log(`  ${t}: ${await count(t)}`);
  }
  console.log('전체 초기화 완료. 모든 유저가 처음부터 다시 시작합니다.');
}

run().catch(e => { console.error('실패:', e.message || e); process.exit(1); });
