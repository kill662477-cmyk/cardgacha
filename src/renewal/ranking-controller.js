import { RARITIES } from './config.js';
import { buildCombatPowerRanking } from './rankings.js';
import { cardVisualChrome } from './card-visual.js';
import { escapeHtml } from './html.js';
import { emblemMarkup } from './guild-emblem.js';

const number = new Intl.NumberFormat('ko-KR');

// 소속 길드를 "엠블럼 [태그] 이름" 형태로 보여 준다. 무소속이면 빈 문자열.
// 이미지 엠블럼을 쓰려면 innerHTML 이어야 하므로, 길드명·태그는 반드시 이스케이프한다.
function guildBadgeMarkup(guild, { showTag = true } = {}) {
  if (!guild || !guild.name) return '';
  const tag = showTag && guild.tag ? `[${escapeHtml(guild.tag)}] ` : '';
  return `<span class="ranking-guild-badge">${emblemMarkup(guild.emblem, 'ranking-guild-emblem')}${tag}${escapeHtml(guild.name)}</span>`;
}
const PODIUM_CARD_IDS = ['kimyunhwan-2', 'tomato-1', 'jidudu-1'];

export function createRankingController({ cards = [], getState, getFormation, getCombatPower, gameService }) {
  const elements = Object.fromEntries([
    'rankingPopulation', 'rankingPodium', 'rankingList', 'rankingNickname',
    'rankingMyRank', 'rankingMyPercentile', 'rankingMyPower', 'rankingTopFiftyGap',
    'rankingProgressBar', 'rankingFormation',
    'rankerDeckDialog', 'rankerDeckEyebrow', 'rankerDeckTitle', 'rankerDeckPower', 'rankerDeckGrid',
    'rankerDeckGuild',
  ].map((id) => [id, document.getElementById(id)]));
  const cardsById = new Map(cards.map((card) => [card.id, card]));
  let renderSequence = 0;
  let cachedRanking = null;

  function imagePath(card) {
    return `assets/cards/${encodeURIComponent(card.file)}`;
  }

  function rowMarkup(entry) {
    return `<li class="${entry.mine ? 'mine' : ''}" data-rank="${entry.rank}" role="button" tabindex="0">
      <b>${entry.rank}</b><span>${escapeHtml(entry.nickname)}</span><strong>${number.format(entry.power)} <small>CP</small></strong>
    </li>`;
  }

  function openRankerDeck(rank) {
    const entry = cachedRanking?.leaders?.find((leader) => leader.rank === rank);
    if (!entry) return;
    const deck = (entry.formation ?? []).map((item) => {
      const id = typeof item === 'string' ? item : item?.cardId;
      const card = cardsById.get(id);
      if (!card) return null;
      const enhancement = typeof item === 'string' ? 0 : Number(item?.enhancement) || 0;
      return { ...card, enhancement };
    }).filter(Boolean);
    elements.rankerDeckEyebrow.textContent = `${entry.rank}위 · ${entry.nickname}`;
    // 길드는 별도 줄로 크게 보여 준다. 태그는 길어서 여기선 빼고 엠블럼 + 길드명만 쓴다.
    const guildBadge = guildBadgeMarkup(entry.guild, { showTag: false });
    elements.rankerDeckGuild.hidden = !guildBadge;
    elements.rankerDeckGuild.innerHTML = guildBadge;
    elements.rankerDeckTitle.textContent = `${entry.nickname}님의 편성`;
    elements.rankerDeckPower.textContent = `전투력 ${number.format(entry.power)}`;
    elements.rankerDeckGrid.innerHTML = deck.length ? deck.map((card) => `<figure class="card-visual" data-rarity="${card.rarity}" data-stars="${card.enhancement}" style="--rarity:${RARITIES[card.rarity].color}">
      <img class="card-photo" src="${imagePath(card)}" alt="${escapeHtml(card.member)}">${cardVisualChrome(card)}<figcaption>${escapeHtml(card.member)}</figcaption>
    </figure>`).join('') : '<p class="ranking-note">편성 정보를 아직 확인할 수 없습니다.</p>';
    window.lucide?.createIcons();
    elements.rankerDeckDialog.showModal();
  }

  elements.rankerDeckDialog.addEventListener('click', () => elements.rankerDeckDialog.close());

  function bindRankerDeckClicks(container) {
    container.addEventListener('click', (event) => {
      const target = event.target.closest('[data-rank]');
      if (!target) return;
      openRankerDeck(Number(target.dataset.rank));
    });
    container.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      const target = event.target.closest('[data-rank]');
      if (!target) return;
      event.preventDefault();
      openRankerDeck(Number(target.dataset.rank));
    });
  }
  bindRankerDeckClicks(elements.rankingPodium);
  bindRankerDeckClicks(elements.rankingList);

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
      return `<article class="ranking-podium-item rank-${entry.rank}${entry.mine ? ' mine' : ''}" data-rank="${entry.rank}" role="button" tabindex="0">
        <span>${entry.rank}위</span><div class="ranking-podium-emblem"><i data-lucide="${entry.rank === 1 ? 'crown' : 'medal'}"></i></div>${cardMarkup}<div class="ranking-podium-copy"><strong>${escapeHtml(entry.nickname)}</strong><b>${number.format(entry.power)} CP</b></div>
      </article>`;
    }).join('');
    elements.rankingList.innerHTML = ranking.leaders.slice(3).map(rowMarkup).join('');
    const myGuildBadge = guildBadgeMarkup(ranking.player.guild);
    const myNickname = escapeHtml(ranking.player.nickname ?? state.nickname);
    elements.rankingNickname.innerHTML = myGuildBadge ? `${myNickname}  ${myGuildBadge}` : myNickname;
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
