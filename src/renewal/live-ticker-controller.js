import { RARITIES } from './config.js';
import { escapeHtml } from './html.js';

export const LIVE_EVENT_TTL_MS = 10 * 60 * 1000;
const HIGH_RARITIES = new Set(['S', 'SS', 'SSS']);
const MAX_EVENTS = 20;
const SEMANTIC_DEDUPE_MS = 15 * 1000;

function timestamp(value) {
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
}

export function normalizeLiveEvent(raw = {}) {
  const eventType = String(raw.eventType ?? raw.event_type ?? '');
  const rarity = String(raw.rarity ?? '');
  const enhancement = raw.enhancement == null ? null : Number(raw.enhancement);
  const createdAt = String(raw.createdAt ?? raw.created_at ?? '');
  const event = {
    id: String(raw.id ?? ''),
    eventType,
    nickname: String(raw.nickname ?? '').trim().slice(0, 40),
    cardId: String(raw.cardId ?? raw.card_id ?? '').trim().slice(0, 80),
    member: String(raw.member ?? '').trim().slice(0, 40),
    rarity,
    enhancement,
    createdAt,
    createdAtMs: timestamp(createdAt),
  };
  if (!event.nickname || !event.cardId || !event.member || !event.createdAtMs) return null;
  if (eventType === 'card_draw' && HIGH_RARITIES.has(rarity)) return event;
  if (eventType === 'nine_star_success' && enhancement === 9 && RARITIES[rarity] && !RARITIES[rarity].displayOnly) return event;
  return null;
}

function semanticKey(event) {
  return [event.eventType, event.nickname, event.cardId, event.rarity, event.enhancement ?? ''].join('|');
}

export function mergeLiveEvents(input, now = Date.now()) {
  const normalized = input.map(normalizeLiveEvent).filter(Boolean)
    .filter((event) => event.createdAtMs <= now + 60_000 && now - event.createdAtMs <= LIVE_EVENT_TTL_MS)
    .sort((left, right) => right.createdAtMs - left.createdAtMs || right.id.localeCompare(left.id));
  const recentByMeaning = new Map();
  const result = [];
  normalized.forEach((event) => {
    if (result.length >= MAX_EVENTS) return;
    const key = semanticKey(event);
    const previousTime = recentByMeaning.get(key);
    if (previousTime != null && previousTime - event.createdAtMs < SEMANTIC_DEDUPE_MS) return;
    recentByMeaning.set(key, event.createdAtMs);
    result.push(event);
  });
  return result;
}

export function liveEventMarkup(event) {
  const color = RARITIES[event.rarity]?.color ?? '#c8f52e';
  const label = event.eventType === 'nine_star_success' ? '9 STAR' : event.rarity;
  const action = event.eventType === 'nine_star_success'
    ? `<em>${escapeHtml(event.member)} ${escapeHtml(event.rarity)}</em> 카드 9성 강화에 성공했습니다!`
    : `<em>${escapeHtml(event.member)} ${escapeHtml(event.rarity)}</em> 카드를 획득했습니다!`;
  return `<span class="live-ticker-item" data-event-type="${event.eventType}" style="--ticker-rarity:${color}"><span class="live-ticker-grade">${label}</span><strong>${escapeHtml(event.nickname)}</strong>님이 ${action}</span>`;
}

export function createLiveTickerController({ runtime = null, getNickname = () => '', now = () => Date.now() } = {}) {
  const ticker = document.getElementById('liveTicker');
  const track = document.getElementById('liveTickerTrack');
  let events = [];
  let unsubscribe = () => {};
  let pruneTimer = 0;

  function render() {
    if (!ticker || !track) return;
    events = mergeLiveEvents(events, now());
    if (!events.length) {
      ticker.dataset.state = 'idle';
      ticker.style.removeProperty('--ticker-accent');
      track.textContent = '고등급 카드 및 9성 강화 기록 대기 중';
      track.style.removeProperty('--ticker-duration');
      return;
    }
    ticker.dataset.state = 'live';
    ticker.style.setProperty('--ticker-accent', RARITIES[events[0].rarity]?.color ?? '#c8f52e');
    const repeated = events.length < 4 ? [...events, ...events, ...events] : events;
    track.innerHTML = repeated.map(liveEventMarkup).join('');
    const characters = repeated.reduce((sum, event) => sum + event.nickname.length + event.member.length + 26, 0);
    track.style.setProperty('--ticker-duration', `${Math.max(20, Math.min(58, characters * .18))}s`);
  }

  function push(raw) {
    events = mergeLiveEvents([raw, ...events], now());
    render();
  }

  function pushCardDraws(drawnCards = []) {
    const createdAt = now();
    drawnCards.filter((card) => HIGH_RARITIES.has(card?.rarity)).forEach((card, index) => push({
      id: `local-draw-${createdAt}-${index}-${card.id}`,
      eventType: 'card_draw',
      nickname: getNickname(),
      cardId: card.id,
      member: card.member,
      rarity: card.rarity,
      createdAt: new Date(createdAt + index).toISOString(),
    }));
  }

  function pushNineStar(card) {
    if (!card || !RARITIES[card.rarity] || RARITIES[card.rarity].displayOnly) return;
    const createdAt = now();
    push({
      id: `local-nine-${createdAt}-${card.id}`,
      eventType: 'nine_star_success',
      nickname: getNickname(),
      cardId: card.id,
      member: card.member,
      rarity: card.rarity,
      enhancement: 9,
      createdAt: new Date(createdAt).toISOString(),
    });
  }

  async function backfill() {
    if (!runtime?.getLiveEvents) return;
    try {
      const latest = await runtime.getLiveEvents();
      events = mergeLiveEvents([...(latest ?? []), ...events], now());
    } catch { /* keep showing whatever we already have */ }
    render();
  }

  async function start() {
    render();
    await backfill();
    // Paid plan: push-instant via a single realtime channel (INSERT on gacha_s2_live_events).
    if (runtime?.subscribeLiveEvents) unsubscribe = runtime.subscribeLiveEvents(push);
    // Age TTL-expired items out of the ticker even when no new events arrive.
    pruneTimer = window.setInterval(render, 60_000);
  }

  function stop() {
    unsubscribe();
    unsubscribe = () => {};
    if (pruneTimer) window.clearInterval(pruneTimer);
    pruneTimer = 0;
  }

  return { start, stop, push, pushCardDraws, pushNineStar };
}
