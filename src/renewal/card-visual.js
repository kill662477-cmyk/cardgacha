export const ENHANCEMENT_STAR_PATH = 'assets/renewal/ui/enhancement-star.webp';

export function normalizeEnhancement(value) {
  return Math.max(0, Math.min(9, Math.floor(Number(value) || 0)));
}

export function enhancementTier(value) {
  const level = normalizeEnhancement(value);
  if (level === 9) return 'max';
  if (level >= 7) return 'high';
  if (level >= 4) return 'mid';
  if (level >= 1) return 'low';
  return 'zero';
}

export function enhancementLabel(value) {
  return `${normalizeEnhancement(value)}성`;
}

export function cardFramePath(rarity) {
  const key = String(rarity || 'F').toLowerCase();
  const supported = ['f', 'e', 'd', 'c', 'b', 'a', 's', 'ss', 'sss', 'ex'];
  return `assets/renewal/card-frames/card-frame-${supported.includes(key) ? key : 'common'}.webp`;
}

export function rarityMarkMarkup(rarity) {
  return `<span class="card-rarity-mark" data-rarity="${rarity}" aria-label="${rarity} 등급">${rarity}</span>`;
}

export function enhancementStarMarkup(value, { inline = false } = {}) {
  const level = normalizeEnhancement(value);
  if (level === 0) return '';
  const tier = enhancementTier(level);
  return `<span class="card-star-mark${inline ? ' inline' : ''}" data-star-tier="${tier}" data-star-level="${level}" aria-label="${enhancementLabel(level)} 강화" title="${enhancementLabel(level)} 강화"><img src="${ENHANCEMENT_STAR_PATH}" alt=""><b>×${level}</b>${level === 9 ? '<i>MAX</i>' : ''}</span>`;
}

export function cardVisualChrome(card, { showEnhancement = true, showFrame = true } = {}) {
  const frame = showFrame
    ? `<img class="card-frame-overlay" src="${cardFramePath(card.rarity)}" alt="" aria-hidden="true">`
    : '';
  return `${frame}${rarityMarkMarkup(card.rarity)}${showEnhancement ? enhancementStarMarkup(card.enhancement) : ''}`;
}
