import {
  GAME_ERROR_CODES,
  createGameError,
  createGameSuccess,
  stableCommandFingerprint,
  validateGameCommand,
} from './service-contract.js';
import { assertRuntimeAdapter, createSystemClock, createSystemRng } from './runtime.js';

const clone = (value) => globalThis.structuredClone ? globalThis.structuredClone(value) : JSON.parse(JSON.stringify(value));

export function createInMemoryCommandGateway(options = {}) {
  const clock = assertRuntimeAdapter(options.clock ?? createSystemClock(), 'now', 'clock');
  const rng = assertRuntimeAdapter(options.rng ?? createSystemRng(), 'next', 'rng');
  const handlers = options.handlers ?? {};
  const validateSnapshot = options.validateSnapshot ?? (() => true);
  const processed = new Map();
  let snapshot = clone(options.initialSnapshot);

  async function execute(command) {
    const serverTime = clock.now();
    const validation = validateGameCommand(command);
    if (!validation.valid) {
      return createGameError({
        command,
        code: GAME_ERROR_CODES.VALIDATION_FAILED,
        message: '요청 형식이 올바르지 않습니다.',
        serverTime,
        revision: snapshot.revision,
        details: validation.issues,
      });
    }

    const fingerprint = stableCommandFingerprint(command);
    const previous = processed.get(command.idempotencyKey);
    if (previous) {
      if (previous.fingerprint !== fingerprint) {
        return createGameError({
          command,
          code: GAME_ERROR_CODES.IDEMPOTENCY_KEY_REUSED,
          message: '같은 멱등성 키를 다른 요청에 사용할 수 없습니다.',
          serverTime,
          revision: snapshot.revision,
        });
      }
      return clone(previous.response);
    }

    if (command.expectedRevision !== snapshot.revision) {
      return createGameError({
        command,
        code: GAME_ERROR_CODES.VERSION_CONFLICT,
        message: '다른 기기에서 변경된 최신 기록을 다시 불러와야 합니다.',
        serverTime,
        revision: snapshot.revision,
        latestSnapshot: clone(snapshot),
      });
    }

    const handler = handlers[command.type];
    if (typeof handler !== 'function') {
      return createGameError({
        command,
        code: GAME_ERROR_CODES.COMMAND_REJECTED,
        message: '현재 처리할 수 없는 게임 명령입니다.',
        serverTime,
        revision: snapshot.revision,
      });
    }

    try {
      const outcome = await handler({ command: clone(command), snapshot: clone(snapshot), serverTime, rng: () => rng.next() });
      const nextSnapshot = clone(outcome?.snapshot);
      nextSnapshot.revision = snapshot.revision + 1;
      validateSnapshot(nextSnapshot);
      snapshot = nextSnapshot;
      const response = createGameSuccess({
        command,
        revision: snapshot.revision,
        serverTime,
        serverSeed: Math.floor(rng.next() * 0x100000000),
        snapshot: clone(snapshot),
        result: clone(outcome?.result ?? {}),
      });
      processed.set(command.idempotencyKey, { fingerprint, response: clone(response) });
      return response;
    } catch (error) {
      return createGameError({
        command,
        code: error?.code ?? GAME_ERROR_CODES.COMMAND_REJECTED,
        message: error?.message ?? '게임 명령이 거부되었습니다.',
        serverTime,
        revision: snapshot.revision,
        details: error?.details ?? null,
      });
    }
  }

  return {
    execute,
    getSnapshot: () => clone(snapshot),
    getProcessedCount: () => processed.size,
  };
}
