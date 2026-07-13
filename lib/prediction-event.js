const CIVIL_WAR_EVENT = {
  id: 'cammon-civil-war-2026-07-14',
  title: '캄몬 시빌워 승자예측 이벤트',
  options: ['변현제팀', '김민철팀'],
  rewardPoints: 3000,
  closesAt: '2026-07-14T10:30:00.000Z', // 2026-07-14 19:30 KST
};

function publicEvent(event, nowMs = Date.now()) {
  const closesAt = event.closes_at || event.closesAt;
  const rewardPoints = event.reward_points || event.rewardPoints;
  return {
    id: event.id,
    title: event.title,
    options: event.options || [],
    rewardPoints,
    closesAt,
    closed: nowMs >= Date.parse(closesAt),
    winningOption: event.winning_option || event.winningOption || null,
    settledAt: event.settled_at || event.settledAt || null,
  };
}

module.exports = { CIVIL_WAR_EVENT, publicEvent };
