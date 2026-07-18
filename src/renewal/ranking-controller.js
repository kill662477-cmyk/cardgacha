import { RARITIES } from './config.js';
import { buildCombatPowerRanking } from './rankings.js';
import { cardVisualChrome } from './card-visual.js';
import { escapeHtml } from './html.js';

const number = new Intl.NumberFormat('ko-KR');
const PODIUM_CARD_IDS = ['kimyunhwan-2', 'tomato-1', 'jidudu-1'];

export function createRankingController({ cards = [], getState, getFormation, getCombatPower, gameService }) {
  const elements = Object.fromEntries([
    'rankingPopulation', 'rankingPodium', 'rankingList', 'rankingNickname',
    'rankingMyRank', 'rankingMyPercentile', 'rankingMyPower', 'rankingTopFiftyGap',
    'rankingProgressBar', 'rankingFormation',
  ].map((id) => [id, document.getElementById(id)]));

  function imagePath(card) {
    return `assets/cards/${encodeURIComponent(card.file)}`;
  }

  function rowMarkup(entry) {
    return `<li class="${entry.mine ? 'mine' : ''}">
      <b>${entry.rank}</b><span>${escapeHtml(entry.nickname)}</span><strong>${number.format(entry.power)} <small>CP</small></strong>
    </li>`;
  }

  const cardsById = new Map(cards.map((card) => [card.id, card]));

  function podiumCard(entry, state, formation) {
    if (entry.mine) {
      const representative = cardsById.get(state.representativeCardId);
      if (representative) return { ...representative, ...(state.cardProgress[representative.id] ?? {}) };
      if (formation[0]) return formation[0];
    }
    return cardsById.get(PODIUM_CARD_IDS[entry.rank - 1]) ?? formation[entry.rank - 1] ?? cards[entry.rank - 1];
  }

  function render() {
    const state = getState();
    const combatPower = getCombatPower();
    const ranking = gameService.getPowerRanking(() => buildCombatPowerRanking(state.nickname, combatPower));
    const formation = getFormation();
    const podiumOrder = [ranking.leaders[1], ranking.leaders[0], ranking.leaders[2]].filter(Boolean);
    elements.rankingPopulation.textContent = `${number.format(ranking.population)}명 집계`;
    elements.rankingPodium.innerHTML = podiumOrder.map((entry) => {
      const card = podiumCard(entry, state, formation);
      const cardMarkup = card ? `<figure class="ranking-podium-card card-visual" data-rarity="${card.rarity}" data-stars="${card.enhancement}" style="--rarity:${RARITIES[card.rarity].color}">
        <img class="card-photo" src="${imagePath(card)}" alt="${card.member} 대표카드">${cardVisualChrome(card)}
      </figure>` : '';
      return `<article class="ranking-podium-item rank-${entry.rank}${entry.mine ? ' mine' : ''}">
        <span>${entry.rank}위</span><div class="ranking-podium-emblem"><i data-lucide="${entry.rank === 1 ? 'crown' : 'medal'}"></i></div>${cardMarkup}<div class="ranking-podium-copy"><strong>${escapeHtml(entry.nickname)}</strong><b>${number.format(entry.power)} CP</b></div>
      </article>`;
    }).join('');
    elements.rankingList.innerHTML = ranking.leaders.slice(3).map(rowMarkup).join('');
    elements.rankingNickname.textContent = state.nickname;
    elements.rankingMyRank.textContent = number.format(ranking.player.rank);
    elements.rankingMyPercentile.textContent = `상위 ${ranking.player.topPercent.toFixed(1)}%`;
    elements.rankingMyPower.textContent = number.format(ranking.player.power);
    elements.rankingTopFiftyGap.textContent = ranking.powerToTopFifty > 0
      ? `TOP 50까지 +${number.format(ranking.powerToTopFifty)} CP`
      : 'TOP 50 진입 완료';
    const progress = ranking.powerToTopFifty > 0
      ? Math.min(100, ranking.player.power / ranking.topFiftyPower * 100)
      : 100;
    elements.rankingProgressBar.style.width = `${progress}%`;
    elements.rankingFormation.innerHTML = formation.map((card) => `<figure class="card-visual" data-rarity="${card.rarity}" data-stars="${card.enhancement}" style="--rarity:${RARITIES[card.rarity].color}">
      <img class="card-photo" src="${imagePath(card)}" alt="${card.member}">${cardVisualChrome(card)}<figcaption>${card.member}</figcaption>
    </figure>`).join('');
    window.lucide?.createIcons();
  }

  return { render };
}
