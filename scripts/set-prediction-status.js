// 승자예측 수동 마감 관리: node scripts/set-prediction-status.js <open|close> --confirm
const { REST, headers, sbFetch } = require('../lib/supabase');
const { CIVIL_WAR_EVENT } = require('../lib/prediction-event');

async function run() {
  const action = (process.argv[2] || '').trim().toLowerCase();
  if (!['open', 'close'].includes(action) || !process.argv.includes('--confirm')) {
    console.log('사용법: node scripts/set-prediction-status.js <open|close> --confirm');
    process.exit(1);
  }

  const rows = await sbFetch(
    `${REST}/gacha_prediction_events?id=eq.${encodeURIComponent(CIVIL_WAR_EVENT.id)}&select=id,settled_at`,
    { headers: headers() }
  );
  const event = rows?.[0];
  if (!event) throw new Error('예측 이벤트를 찾을 수 없습니다');
  if (action === 'open' && event.settled_at) throw new Error('정산 완료된 이벤트는 다시 열 수 없습니다');

  const closesAt = action === 'open' ? CIVIL_WAR_EVENT.closesAt : new Date().toISOString();
  await sbFetch(`${REST}/gacha_prediction_events?id=eq.${encodeURIComponent(CIVIL_WAR_EVENT.id)}`, {
    method: 'PATCH',
    headers: headers({ Prefer: 'return=minimal' }),
    body: JSON.stringify({ closes_at: closesAt }),
  });
  console.log(action === 'open' ? '완료: 마감 미정 상태로 오픈' : `완료: ${closesAt} 마감`);
}

run().catch(error => { console.error('실패:', error.message || error); process.exit(1); });
