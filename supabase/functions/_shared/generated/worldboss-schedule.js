import { WORLD_BOSS_RULES } from './config.js';

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

function pad2(value) {
  return String(value).padStart(2, '0');
}

function buildSlot(year, month, date, hour, rules) {
  const startsAt = Date.UTC(year, month, date, hour, 0, 0, 0) - KST_OFFSET_MS;
  return {
    id: `noise-zero-${year}${pad2(month + 1)}${pad2(date)}-${pad2(hour)}`,
    startsAt,
    endsAt: startsAt + rules.eventDurationSeconds * 1000,
  };
}

export function kstSlotLabel(ms) {
  const kst = new Date(ms + KST_OFFSET_MS);
  return `${pad2(kst.getUTCHours())}:${pad2(kst.getUTCMinutes())}`;
}

export function resolveWorldBossSlot(now, rules = WORLD_BOSS_RULES) {
  const hours = [...rules.scheduleHours].sort((left, right) => left - right);
  const kst = new Date(now + KST_OFFSET_MS);
  const year = kst.getUTCFullYear();
  const month = kst.getUTCMonth();
  const date = kst.getUTCDate();

  let liveSlot = null;
  let nextSlot = null;
  for (const hour of hours) {
    const slot = buildSlot(year, month, date, hour, rules);
    if (!liveSlot && now >= slot.startsAt && now < slot.endsAt) liveSlot = slot;
    if (!nextSlot && slot.startsAt > now) nextSlot = { id: slot.id, startsAt: slot.startsAt };
  }
  if (!nextSlot) {
    const tomorrow = new Date(now + KST_OFFSET_MS + DAY_MS);
    const slot = buildSlot(tomorrow.getUTCFullYear(), tomorrow.getUTCMonth(), tomorrow.getUTCDate(), hours[0], rules);
    nextSlot = { id: slot.id, startsAt: slot.startsAt };
  }
  return { live: Boolean(liveSlot), slot: liveSlot, nextSlot };
}
