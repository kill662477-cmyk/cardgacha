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
  const cardsById = new Map(cards.map((card) => [card.id, card]));
  let renderSequence = 0;
  let cachedRanking = null;

  function imagePath(card) {
    return `assets/cards/${encodeURIComponent(card.file)}`;
  }

  function rowMarkup(entry) {
    return `<li class="${entry.mine ? 'mine' : ''}">
      <b>${entry.rank}</b><span>${escapeHtml(entry.nickname)}</span><strong>${number.format(entry.power)} <small>CP</small></strong>
    </li>`;
  }

  function podiumCard(entry, state, formation) {
    const rankedRepresentative = cardsById.get(entry.representativeCardId);
    if (rankedRepresentative) return rankedRepresentative;
    if (entry.mine) {
      const representative = cardsById.get(state.representativeCardId);
      if (representative) return { ...representative, ...(state.cardProgress[representative.id] ?? {}) };
      if (formation[0]) return formation[0];
    }
    return cardsById.get(PODIUM_CARD_IDS[entry.rank - 1]) ?? formation[entry.rank - 1] ?? cards[entry.rank - 1];
  }

  function applyRanking(ranking) {
    if (!ranking?.player || !Array.isArray(ranking.leaders)) return;
    const state = getState();
    const formation = getFormation();
    const podiumOrder = [ranking.leaders[1], ranking.leaders[0], ranking.leaders[2]].filter(Boolean);
    elements.rankingPopulation.textContent = `${number.format(ranking.population)}명 집계`;
    elements.rankingPodium.innerHTML = podiumOrder.map((entry) => {
      const card = podiumCard(entry, state, formation);
      const cardMarkup = card ? `<figure class="ranking-podium-card card-visual" data-rarity="${card.rarity}" data-stars="${card.enhancement ?? 0}" style="--rarity:${RARITIES[card.rarity].color}">
        <img class="card-photo" src="${imagePath(card)}" alt="${escapeHtml(card.member)} 대표 카드">${cardVisualChrome(card)}
      </figure>` : '';
      return `<article class="ranking-podium-item rank-${entry.rank}${entry.mine ? ' mine' : ''}">
        <span>${entry.rank}위</span><div class="ranking-podium-emblem"><i data-lucide="${entry.rank === 1 ? 'crown' : 'medal'}"></i></div>${cardMarkup}<div class="ranking-podium-copy"><strong>${escapeHtml(entry.nickname)}</strong><b>${number.format(entry.power)} CP</b></div>
      </article>`;
    }).join('');
    elements.rankingList.innerHTML = ranking.leaders.slice(3).map(rowMarkup).join('');
    elements.rankingNickname.textContent = ranking.player.nickname ?? state.nickname;
    elements.rankingMyRank.textContent = ranking.player.rank ? number.format(ranking.player.rank) : '-';
    elements.rankingMyPercentile.textContent = `상위 ${Number(ranking.player.topPercent ?? 100).toFixed(1)}%`;
    elements.rankingMyPower.textContent = number.format(ranking.player.power ?? 0);
    elements.rankingTopFiftyGap.textContent = ranking.powerToTopFifty > 0
      ? `TOP 50까지 +${number.format(ranking.powerToTopFifty)} CP`
      : 'TOP 50 진입 완료';
    const progress = ranking.powerToTopFifty > 0 && ranking.topFiftyPower > 0
      ? Math.min(100, ranking.player.power / ranking.topFiftyPower * 100)
      : 100;
    elements.rankingProgressBar.style.width = `${progress}%`;
    elements.rankingFormation.innerHTML = formation.map((card) => `<figure class="card-visual" data-rarity="${card.rarity}" data-stars="${card.enhancement}" style="--rarity:${RARITIES[card.rarity].color}">
      <img class="card-photo" src="${imagePath(card)}" alt="${escapeHtml(card.member)}">${cardVisualChrome(card)}<figcaption>${escapeHtml(card.member)}</figcaption>
    </figure>`).join('');
    window.lucide?.createIcons();
  }

  function render() {
    const state = getState();
    const combatPower = getCombatPower();
    const request = gameService.getPowerRanking(() => buildCombatPowerRanking(state.nickname, combatPower));
    if (!request || typeof request.then !== 'function') {
      cachedRanking = request;
      applyRanking(request);
      return;
    }
    const sequence = ++renderSequence;
    if (cachedRanking) applyRanking(cachedRanking);
    else elements.rankingPopulation.textContent = '서버 랭킹 동기화 중';
    request.then((ranking) => {
      if (sequence !== renderSequence || ranking?.ok === false) return;
      cachedRanking = ranking;
      applyRanking(ranking);
    }).catch(() => {
      if (sequence === renderSequence && !cachedRanking) elements.rankingPopulation.textContent = '랭킹 연결 실패';
    });
  }

  return { render };
}
