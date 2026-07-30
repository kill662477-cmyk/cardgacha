const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '::1']);

export function isLocalTestHost(hostname = globalThis.location?.hostname ?? '') {
  return LOCAL_HOSTS.has(hostname);
}

export function applyLocalTestProfile(state, cards, hostname = globalThis.location?.hostname ?? '') {
  if (!isLocalTestHost(hostname)) return false;
  if ((Number(state.revision) || 0) > 0) return false;
  state.nickname = 'MSTZ';
  // nolevel-1: accountLevel/accountExp 제거.
  state.actionEnergy = state.maxActionEnergy ?? state.actionEnergy;
  state.points = 1_000_000;
  state.pendingPoints = 0;
  state.lastRewardAt = Date.now();
  if (state.supportItems) Object.keys(state.supportItems).forEach((key) => { state.supportItems[key] = 0; });
  // 이벤트 전용 선택권은 로컬에서 지급·선택 흐름을 바로 검수할 수 있게 각 1개만 제공한다.
  if (state.supportItems) {
    state.supportItems.ssCardSelector = 1;
    state.supportItems.sssCardSelector = 1;
  }
  state.cardProgress ??= {};
  cards.forEach((card) => { state.cardCopies[card.id] = 1; });
  state.collectionRecords = Object.fromEntries(cards.map((card) => [card.id, true]));
  // 최종 콘텐츠를 로컬에서 즉시 검수할 수 있는 기준 편성.
  const hellFormation = ['juharang-2', 'kimyunhwan-4', 'jjiking-12', 'tomato-11', 'kimmincheol-7'];
  state.formation = hellFormation;
  hellFormation.forEach((cardId) => { state.cardProgress[cardId] = { enhancement: 9, exp: 0 }; });
  state.clearedStage = 110;
  state.guildBuff = { guildId: 'local-hell-qa', level: 10, atk: 0.05, hp: 0.05, def: 0.04, points: 0.05 };
  return true;
}
