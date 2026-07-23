import { GAME_ERROR_CODES } from './service-contract.js';

/**
 * Retries a command once after synchronizing the server snapshot. A
 * VERSION_CONFLICT is returned before mutation, so one replay is safe.
 */
export async function executeCommandWithVersionRetry({
  type,
  payload,
  sendCommand,
  getRevision,
  applySnapshot,
  retryOnVersionConflict = true,
}) {
  if (typeof sendCommand !== 'function' || typeof getRevision !== 'function' || typeof applySnapshot !== 'function') {
    throw new TypeError('Server command retry adapters are required.');
  }

  async function sendOnce() {
    const response = await sendCommand(type, payload, getRevision());
    if (response?.ok && response.snapshot) applySnapshot(response.snapshot);
    else if (response?.code === GAME_ERROR_CODES.VERSION_CONFLICT && response.latestSnapshot) applySnapshot(response.latestSnapshot);
    return response;
  }

  const first = await sendOnce();
  if (!retryOnVersionConflict
    || first?.code !== GAME_ERROR_CODES.VERSION_CONFLICT
    || !first.latestSnapshot) return first;
  return sendOnce();
}
