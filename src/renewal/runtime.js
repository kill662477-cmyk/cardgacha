export function createSystemClock() {
  return { now: () => Date.now() };
}

export function createSystemRng() {
  return { next: () => Math.random() };
}

export function assertRuntimeAdapter(adapter, method, label) {
  if (!adapter || typeof adapter[method] !== 'function') throw new Error(`${label}.${method} adapter is required.`);
  return adapter;
}
