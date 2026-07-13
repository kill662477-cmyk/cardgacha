// 승자예측 정산: node scripts/settle-prediction.js <변현제팀|김민철팀> --confirm
const { rpc } = require('../lib/supabase');
const { CIVIL_WAR_EVENT } = require('../lib/prediction-event');

async function run() {
  const winner = (process.argv[2] || '').trim();
  if (!CIVIL_WAR_EVENT.options.includes(winner) || !process.argv.includes('--confirm')) {
    console.log(`사용법: node scripts/settle-prediction.js <${CIVIL_WAR_EVENT.options.join('|')}> --confirm`);
    process.exit(1);
  }
  const rows = await rpc('gacha_settle_prediction_event', {
    p_event_id: CIVIL_WAR_EVENT.id,
    p_winning_option: winner,
  });
  const result = rows?.[0];
  if (!result) throw new Error('정산 결과를 확인할 수 없습니다');
  if (result.already_settled) {
    console.log(`이미 정산됨: ${winner}, 추가 지급 없음`);
    return;
  }
  console.log(`완료: ${winner} 정답자 ${result.awarded_count}명에게 각 +${result.reward_points}P 지급`);
}

run().catch(e => { console.error('실패:', e.message || e); process.exit(1); });
