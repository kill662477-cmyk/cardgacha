import { BALANCE_VERSION, STAGES } from './config.js';
import { simulateBattle } from './battle.js';
import { calculateCollectionBonuses } from './collection.js';
import { simulateWorldBossAttempt } from './worldboss.js';
import {
  GAME_COMMAND_TYPES,
  GAME_ERROR_CODES,
  createGameError,
  validateGameCommand,
} from './service-contract.js';

const DIRECT_RPCS = Object.freeze({
  [GAME_COMMAND_TYPES.UPDATE_FORMATION]: 'gacha_s2_update_formation',
  [GAME_COMMAND_TYPES.PURCHASE_PACK]: 'gacha_s2_purchase_pack',
  [GAME_COMMAND_TYPES.PURCHASE_SUPPORT_PACK]: 'gacha_s2_purchase_support_pack',
  [GAME_COMMAND_TYPES.USE_SUPPORT_ITEM]: 'gacha_s2_use_support_item',
  [GAME_COMMAND_TYPES.ENHANCE_CARD]: 'gacha_s2_enhance_card',
  [GAME_COMMAND_TYPES.SET_REPRESENTATIVE_CARD]: 'gacha_s2_set_representative_card',
  [GAME_COMMAND_TYPES.SET_CARD_LOCK]: 'gacha_s2_set_card_lock',
  [GAME_COMMAND_TYPES.FINISH_ADVENTURE_RUN]: 'gacha_s2_finish_adventure_run',
  [GAME_COMMAND_TYPES.START_MINIGAME]: 'gacha_s2_start_minigame',
  [GAME_COMMAND_TYPES.FINISH_MINIGAME]: 'gacha_s2_finish_minigame',
  [GAME_COMMAND_TYPES.CLAIM_WORLD_BOSS_REWARD]: 'gacha_s2_claim_world_boss_reward',
});

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(canonicalJson(value));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function baseArgs(userId, command) {
  return {
    p_user_id: userId,
    p_expected_revision: command.expectedRevision,
    p_idempotency_key: command.idempotencyKey,
  };
}

function directArgs(userId, command) {
  const args = baseArgs(userId, command);
  const payload = command.payload;
  switch (command.type) {
    case GAME_COMMAND_TYPES.UPDATE_FORMATION:
      return { ...args, p_formation: payload.formation };
    case GAME_COMMAND_TYPES.PURCHASE_PACK:
      return {
        ...args,
        p_product_id: payload.productId,
        p_quantity: payload.quantity,
        p_race: payload.race ?? null,
      };
    case GAME_COMMAND_TYPES.PURCHASE_SUPPORT_PACK:
      return { ...args, p_quantity: payload.quantity };
    case GAME_COMMAND_TYPES.USE_SUPPORT_ITEM:
      return {
        ...args,
        p_item_id: payload.itemId,
        p_target_card_id: payload.targetCardId ?? null,
        p_race: payload.race ?? null,
      };
    case GAME_COMMAND_TYPES.ENHANCE_CARD:
      return {
        ...args,
        p_card_id: payload.cardId,
        p_target_enhancement: payload.targetEnhancement,
        p_material_card_ids: payload.materialCardIds,
        p_booster_id: payload.boosterId ?? null,
      };
    case GAME_COMMAND_TYPES.SET_REPRESENTATIVE_CARD:
      return { ...args, p_card_id: payload.cardId };
    case GAME_COMMAND_TYPES.SET_CARD_LOCK:
      return { ...args, p_card_id: payload.cardId, p_locked: payload.locked };
    case GAME_COMMAND_TYPES.FINISH_ADVENTURE_RUN:
      return { ...args, p_run_id: payload.runId };
    case GAME_COMMAND_TYPES.START_MINIGAME:
      return { ...args, p_game: payload.game, p_difficulty: payload.difficulty ?? null };
    case GAME_COMMAND_TYPES.FINISH_MINIGAME:
      return {
        ...args,
        p_run_id: payload.runId,
        p_input_log: payload.inputLog,
        p_claimed_score: payload.score,
      };
    case GAME_COMMAND_TYPES.CLAIM_WORLD_BOSS_REWARD:
      return { ...args, p_event_id: payload.eventId };
    default:
      return args;
  }
}

function commandError(command, code, message, clock, details = null) {
  return createGameError({
    command,
    code,
    message,
    serverTime: clock.now(),
    revision: command?.expectedRevision ?? null,
    details,
  });
}

function formationFromSnapshot(snapshot, cardsById) {
  const formation = Array.isArray(snapshot?.formation) ? snapshot.formation : [];
  if (formation.length !== 5 || new Set(formation).size !== 5) throw new Error('SERVER_FORMATION_INVALID');
  return formation.map((cardId) => {
    const base = cardsById.get(cardId);
    const copies = Number(snapshot.cardCopies?.[cardId] ?? 0);
    if (!base || base.rarity === 'EX' || base.group || copies < 1) throw new Error('SERVER_FORMATION_INVALID');
    const progress = snapshot.cardProgress?.[cardId] ?? {};
    return {
      ...base,
      enhancement: Number(progress.enhancement ?? base.enhancement ?? 0),
      exp: Number(progress.exp ?? base.exp ?? 0),
    };
  });
}

function verifiedAdventureClears(formation, bonuses) {
  let cleared = 0;
  for (const stage of STAGES) {
    if (!simulateBattle(formation, stage, bonuses).victory) break;
    cleared += 1;
  }
  return cleared;
}

export function createServerCommandRouter(options) {
  const gateway = options?.gateway;
  const cards = options?.cards;
  const clock = options?.clock ?? { now: () => Date.now() };
  if (!gateway || typeof gateway.rpc !== 'function' || typeof gateway.activeBalanceVersion !== 'function') {
    throw new Error('Server command gateway is required.');
  }
  if (!Array.isArray(cards) || cards.length === 0) throw new Error('Server card catalog is required.');
  const cardsById = new Map(cards.map((card) => [card.id, card]));

  async function loadSnapshot(userId) {
    return gateway.rpc('gacha_s2_get_player_snapshot', { p_user_id: userId });
  }

  async function verifiedContext(userId, command) {
    const [activeVersion, snapshot] = await Promise.all([
      gateway.activeBalanceVersion(),
      loadSnapshot(userId),
    ]);
    if (activeVersion !== BALANCE_VERSION) {
      throw new Error(`BALANCE_VERSION_MISMATCH:${activeVersion ?? 'none'}:${BALANCE_VERSION}`);
    }
    const formation = formationFromSnapshot(snapshot, cardsById);
    const calculated = calculateCollectionBonuses(cards, snapshot.collectionRecords ?? {});
    const bonuses = Object.fromEntries(
      ['attack', 'hp', 'defense', 'bossDamage', 'idle', 'combatTotal'].map((key) => [key, calculated[key]]),
    );
    return { command, snapshot, formation, bonuses };
  }

  async function execute(userId, command) {
    const validation = validateGameCommand(command);
    if (!validation.valid) {
      return commandError(command, GAME_ERROR_CODES.VALIDATION_FAILED, '게임 명령 형식이 올바르지 않습니다.', clock, {
        issues: validation.issues,
      });
    }
    if (typeof userId !== 'string' || !userId) {
      return commandError(command, GAME_ERROR_CODES.AUTH_REQUIRED, '로그인이 필요합니다.', clock);
    }
    try {
      const directRpc = DIRECT_RPCS[command.type];
      if (directRpc) return await gateway.rpc(directRpc, directArgs(userId, command));

      if (command.type === GAME_COMMAND_TYPES.START_ADVENTURE_RUN
        || command.type === GAME_COMMAND_TYPES.CLAIM_QUICK_BATTLE) {
        const context = await verifiedContext(userId, command);
        const clearedStages = verifiedAdventureClears(context.formation, context.bonuses);
        const digest = await sha256({
          balanceVersion: BALANCE_VERSION,
          commandId: command.commandId,
          type: command.type,
          userId,
          formation: context.formation.map((card) => ({ id: card.id, enhancement: card.enhancement })),
          bonuses: context.bonuses,
          clearedStages,
        });
        const rpc = command.type === GAME_COMMAND_TYPES.START_ADVENTURE_RUN
          ? 'gacha_s2_start_adventure_run'
          : 'gacha_s2_claim_quick_battle';
        return await gateway.rpc(rpc, {
          ...baseArgs(userId, command),
          p_verified_cleared_stages: clearedStages,
          p_verification_digest: digest,
        });
      }

      if (command.type === GAME_COMMAND_TYPES.CLAIM_ADVENTURE_REWARDS) {
        const context = await verifiedContext(userId, command);
        return await gateway.rpc('gacha_s2_claim_idle_reward', {
          ...baseArgs(userId, command),
          p_idle_bonus: context.bonuses.idle,
        });
      }

      if (command.type === GAME_COMMAND_TYPES.ATTACK_WORLD_BOSS) {
        const context = await verifiedContext(userId, command);
        const status = await gateway.rpc('gacha_s2_get_world_boss_status', {
          p_user_id: userId,
          p_event_id: command.payload.eventId,
        });
        const attemptNumber = Number(status?.player?.attempts ?? 0) + 1;
        const battle = simulateWorldBossAttempt(
          context.formation,
          context.bonuses,
          attemptNumber,
          command.payload.eventId,
        );
        const digest = await sha256({
          balanceVersion: BALANCE_VERSION,
          commandId: command.commandId,
          type: command.type,
          userId,
          eventId: command.payload.eventId,
          attemptNumber,
          formation: context.formation.map((card) => ({ id: card.id, enhancement: card.enhancement })),
          bonuses: context.bonuses,
          damageByCard: battle.damageByCard,
          totalDamage: battle.totalDamage,
        });
        return await gateway.rpc('gacha_s2_attack_world_boss', {
          ...baseArgs(userId, command),
          p_event_id: command.payload.eventId,
          p_verified_damage: battle.totalDamage,
          p_verification_digest: digest,
        });
      }

      return commandError(command, GAME_ERROR_CODES.COMMAND_REJECTED, '아직 서버 전환되지 않은 명령입니다.', clock);
    } catch (error) {
      options?.onError?.({
        commandId: command.commandId,
        commandType: command.type,
        reason: error?.message ?? String(error),
      });
      return commandError(command, GAME_ERROR_CODES.INTERNAL_ERROR, '게임 서버 명령 처리에 실패했습니다.', clock);
    }
  }

  return { execute, loadSnapshot };
}
