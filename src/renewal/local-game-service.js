import { loadState, resetState, saveState } from './storage.js';
import { assertRuntimeAdapter, createSystemClock, createSystemRng } from './runtime.js';

export const GAME_SERVICE_METHODS = Object.freeze([
  'loadSnapshot', 'resetSnapshot', 'persistSnapshot', 'updateFormation',
  'claimAdventureRewards', 'purchasePack', 'enhanceCard', 'startMinigame',
  'finishMinigame', 'attackWorldBoss', 'claimWorldBossReward', 'getPowerRanking',
  'now', 'random',
]);

export function createLocalGameService(options = {}) {
  const clock = assertRuntimeAdapter(options.clock ?? createSystemClock(), 'now', 'clock');
  const rng = assertRuntimeAdapter(options.rng ?? createSystemRng(), 'next', 'rng');
  let state = options.reset ? resetState(clock.now()) : loadState(clock.now());

  function commit(snapshot = state) {
    saveState(snapshot);
    state = snapshot;
    return state;
  }

  const service = {
    loadSnapshot: () => state,
    resetSnapshot: () => {
      state = resetState(clock.now());
      return state;
    },
    persistSnapshot: commit,
    updateFormation: commit,
    claimAdventureRewards: commit,
    purchasePack: commit,
    enhanceCard: commit,
    startMinigame: commit,
    finishMinigame: commit,
    attackWorldBoss: commit,
    claimWorldBossReward: commit,
    getPowerRanking: (resolver) => resolver(state),
    now: () => clock.now(),
    random: () => rng.next(),
  };

  GAME_SERVICE_METHODS.forEach((method) => {
    if (typeof service[method] !== 'function') throw new Error(`Local game service missing method: ${method}`);
  });
  return service;
}
