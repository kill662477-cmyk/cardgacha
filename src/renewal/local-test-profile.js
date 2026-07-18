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
  cards.forEach((card) => { state.cardCopies[card.id] = 0; });
  state.collectionRecords = {};
  return true;
}
