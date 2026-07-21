import { GAME_ERROR_CODES, createGameError, isRetryableGameError } from './service-contract.js';

export const REQUEST_PHASES = Object.freeze({
  IDLE: 'idle',
  PENDING: 'pending',
  SUCCESS: 'success',
  ERROR: 'error',
  OFFLINE: 'offline',
  AUTH: 'auth',
  CONFLICT: 'conflict',
});

function phaseForResponse(response) {
  if (response?.ok !== false) return REQUEST_PHASES.SUCCESS;
  if (response.code === GAME_ERROR_CODES.OFFLINE) return REQUEST_PHASES.OFFLINE;
  if (response.code === GAME_ERROR_CODES.AUTH_REQUIRED) return REQUEST_PHASES.AUTH;
  if (response.code === GAME_ERROR_CODES.VERSION_CONFLICT) return REQUEST_PHASES.CONFLICT;
  if (response.code === GAME_ERROR_CODES.COMMAND_REJECTED || response.code === GAME_ERROR_CODES.VALIDATION_FAILED) {
    return REQUEST_PHASES.SUCCESS;
  }
  return REQUEST_PHASES.ERROR;
}

export function createRequestCoordinator(options = {}) {
  const clock = options.clock ?? { now: () => Date.now() };
  const isOnline = options.isOnline ?? (() => globalThis.navigator?.onLine !== false);
  const onTransition = options.onTransition ?? (() => {});
  const pending = new Map();
  const states = new Map();
  let lastFailure = null;

  function transition(operation, phase, extra = {}) {
    const next = { operation, phase, changedAt: clock.now(), ...extra };
    states.set(operation, next);
    onTransition(next);
    return next;
  }

  function run(operation, task, metadata = {}) {
    if (pending.has(operation)) return pending.get(operation);
    if (typeof task !== 'function') throw new Error('Request task is required.');

    if (!isOnline()) {
      const response = createGameError({
        code: GAME_ERROR_CODES.OFFLINE,
        message: '네트워크 연결이 없습니다.',
        serverTime: clock.now(),
      });
      lastFailure = { operation, task, metadata, response };
      transition(operation, REQUEST_PHASES.OFFLINE, { response, retryable: true, metadata });
      return Promise.resolve(response);
    }

    transition(operation, REQUEST_PHASES.PENDING, { retryable: false, metadata });
    const request = Promise.resolve()
      .then(task)
      .then((value) => {
        const response = value?.ok === false || value?.ok === true ? value : { ok: true, value };
        const phase = phaseForResponse(response);
        if (phase === REQUEST_PHASES.SUCCESS) {
          lastFailure = null;
          transition(operation, phase, { response, retryable: false, metadata });
        } else {
          const retryable = isRetryableGameError(response);
          lastFailure = { operation, task, metadata, response };
          transition(operation, phase, { response, retryable, metadata });
        }
        return response;
      })
      .catch((error) => {
        const offline = !isOnline();
        const response = createGameError({
          code: offline ? GAME_ERROR_CODES.OFFLINE : GAME_ERROR_CODES.INTERNAL_ERROR,
          message: offline ? '네트워크 연결이 끊겼습니다.' : '요청 처리 중 오류가 발생했습니다.',
          serverTime: clock.now(),
          details: { name: error?.name ?? 'Error', message: error?.message ?? String(error) },
        });
        lastFailure = { operation, task, metadata, response };
        transition(operation, offline ? REQUEST_PHASES.OFFLINE : REQUEST_PHASES.ERROR, {
          response,
          retryable: true,
          metadata,
        });
        return response;
      })
      .finally(() => pending.delete(operation));
    pending.set(operation, request);
    return request;
  }

  function retryLast() {
    if (!lastFailure?.response?.retryable) return Promise.resolve(null);
    return run(lastFailure.operation, lastFailure.task, lastFailure.metadata);
  }

  return {
    run,
    retryLast,
    getState: (operation) => states.get(operation) ?? { operation, phase: REQUEST_PHASES.IDLE },
    isPending: (operation) => pending.has(operation),
    hasRetryableFailure: () => Boolean(lastFailure?.response?.retryable),
  };
}
