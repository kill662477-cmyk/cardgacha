import { RARITIES } from './config.js';
import { applyCardExperience } from './rewards.js';
import { cardVisualChrome } from './card-visual.js';
import { escapeHtml } from './html.js';
import {
  WORLD_BOSS_RULES,
  claimWorldBossReward,
  getWorldBossReward,
  getWorldBossSnapshot,
  normalizeWorldBossProgress,
  recordWorldBossAttempt,
  simulateWorldBossAttempt,
} from './worldboss.js';
import { kstSlotLabel } from './worldboss-schedule.js';
import { bonusDropText, grantBonusDrop, rollWorldBossBonusDrop } from './bonus-loot.js';

const number = new Intl.NumberFormat('ko-KR');
const rankNames = ['전파도시_루키', 'Fresh민트', 'Calm_브로커', '암흑신호', 'MSTZ_손실바'];
const rankDamage = [48_250_000, 39_870_000, 32_410_000, 26_730_000, 21_940_000];

function formatDuration(totalSeconds) {
  const seconds = Math.max(0, Math.ceil(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`;
}

function wait(ms) {
  return new Promise((resolve) => window.setTimeout(resolve, Math.max(0, ms)));
}

export function createWorldBossController({ getState, getFormation, getBonuses, persist, showToast, clock, random, serverCommands = null }) {
  const elements = Object.fromEntries([
    'worldBossScreen', 'worldBossEventState', 'worldBossTimer', 'worldBossClockLabel', 'worldBossNextSlot',
    'worldBossSchedule', 'worldBossPhase',
    'worldBossHpBar', 'worldBossHpText', 'worldBossCore', 'worldBossCorePhase', 'worldBossAttemptDamage',
    'worldBossParty', 'worldBossParticipants', 'worldBossBestDamage', 'worldBossTotalDamage',
    'worldBossAttempts', 'worldBossPercentile', 'worldBossAttackButton', 'worldBossRewardButton',
    'worldBossRewardText', 'worldBossRanking', 'worldBossRecent',
  ].map((id) => [id, document.getElementById(id)]));

  let active = false;
  let running = false;
  let sequence = 0;
  let displayedDamage = 0;

  function imagePath(card) {
    return `assets/cards/${encodeURIComponent(card.file)}`;
  }

  function progress(now = clock.now()) {
    const state = getState();
    state.worldBoss = normalizeWorldBossProgress(state.worldBoss, now);
    return state.worldBoss;
  }

  function renderParty() {
    elements.worldBossParty.innerHTML = getFormation().map((card, index) => `
      <article class="worldboss-card card-visual" data-worldboss-card="${index}" data-rarity="${card.rarity}" data-stars="${card.enhancement}" style="--rarity:${RARITIES[card.rarity].color}">
        <img class="card-photo" src="${imagePath(card)}" alt="${card.member}">${cardVisualChrome(card)}<strong>${card.member}</strong>
      </article>`).join('');
  }

  function percentile(totalDamage) {
    if (totalDamage >= 20_000_000) return '상위 1%';
    if (totalDamage >= 12_000_000) return '상위 5%';
    if (totalDamage >= 5_000_000) return '상위 18%';
    if (totalDamage > 0) return '상위 46%';
    return '미참여';
  }

  function renderRanking(playerDamage) {
    const rows = rankNames.map((name, index) => ({ name, damage: rankDamage[index], mine: false }));
    if (playerDamage > 0) rows.push({ name: getState().nickname, damage: playerDamage, mine: true });
    rows.sort((left, right) => right.damage - left.damage);
    elements.worldBossRanking.innerHTML = rows.slice(0, 6).map((row, index) => `
      <li class="${row.mine ? 'mine' : ''}"><b>${index + 1}</b><span>${escapeHtml(row.name)}</span><strong>${number.format(row.damage)}</strong></li>`).join('');
  }

  function renderRecent(lastDamage) {
    const entries = [
      ['김치신호', 8_421_300], ['테란반장', 6_980_120], ['ZERG_SIGNAL', 5_730_440],
    ];
    if (lastDamage > 0) entries.unshift([getState().nickname, lastDamage]);
    elements.worldBossRecent.innerHTML = entries.slice(0, 3).map(([name, damage]) => `<li><i></i><span>${escapeHtml(name)}</span><b>+${number.format(damage)}</b></li>`).join('');
  }

  function render(now = clock.now()) {
    const current = progress(now);
    const snapshot = getWorldBossSnapshot(current, now);
    const reward = getWorldBossReward(current, now);
    const status = snapshot.resultsOpen
      ? snapshot.defeated ? 'result-success' : 'result-failure'
      : snapshot.active ? 'live' : snapshot.defeated ? 'closed' : 'standby';
    const belowBattleWindow = snapshot.active && snapshot.raidRemainingSeconds <= WORLD_BOSS_RULES.battleDuration;
    elements.worldBossEventState.textContent = snapshot.resultsOpen
      ? snapshot.defeated ? 'RAID CLEAR · RESULT' : 'RAID FAILED · RESULT'
      : snapshot.active ? 'SERVER RAID LIVE' : snapshot.defeated ? 'BOSS DEFEATED' : 'NEXT RAID STANDBY';
    elements.worldBossTimer.textContent = formatDuration(status === 'standby' ? snapshot.secondsUntilStart : snapshot.remainingSeconds);
    elements.worldBossClockLabel.textContent = status === 'standby'
      ? '다음 출현까지'
      : snapshot.resultsOpen ? '결과 종료까지' : '레이드 종료까지';
    if (elements.worldBossSchedule) elements.worldBossSchedule.textContent = `매일 ${WORLD_BOSS_RULES.scheduleHours.join('·')}시 KST`;
    if (elements.worldBossNextSlot) {
      elements.worldBossNextSlot.hidden = status !== 'standby';
      elements.worldBossNextSlot.textContent = status === 'standby' ? `다음 출현 ${kstSlotLabel(snapshot.nextSlot.startsAt)} KST` : '';
    }
    elements.worldBossPhase.textContent = `PHASE ${snapshot.phase}`;
    elements.worldBossHpBar.style.width = `${snapshot.hpRatio * 100}%`;
    elements.worldBossHpText.textContent = `${number.format(snapshot.currentHp)} / ${number.format(snapshot.maxHp)}`;
    elements.worldBossCore.dataset.phase = snapshot.phase;
    elements.worldBossCorePhase.textContent = `PHASE ${snapshot.phase} · ${snapshot.phase === 1 ? '악성 신호 활성' : snapshot.phase === 2 ? '과부하 폭주' : '코어 붕괴 임계'}`;
    if (!running) displayedDamage = current.lastDamage;
    elements.worldBossAttemptDamage.textContent = number.format(displayedDamage);
    elements.worldBossParticipants.textContent = number.format(snapshot.participants);
    elements.worldBossBestDamage.textContent = number.format(current.bestDamage);
    elements.worldBossTotalDamage.textContent = number.format(current.totalDamage);
    elements.worldBossAttempts.textContent = `${Math.max(0, WORLD_BOSS_RULES.maxAttempts - current.attempts)} / ${WORLD_BOSS_RULES.maxAttempts}`;
    elements.worldBossPercentile.textContent = percentile(current.totalDamage);
    elements.worldBossAttackButton.disabled = running || !snapshot.canStartAttempt;
    elements.worldBossAttackButton.querySelector('span').textContent = running
      ? '교전 데이터 전송 중'
      : snapshot.resultsOpen ? snapshot.defeated ? '레이드 성공' : '레이드 실패'
        : !snapshot.active ? snapshot.defeated ? '결과 집계 중' : '월드보스 대기 중'
        : current.attempts >= WORLD_BOSS_RULES.maxAttempts ? '이번 회차 도전 완료'
          : belowBattleWindow ? '회차 종료 임박' : '보스 교전 시작';
    elements.worldBossRewardButton.disabled = !reward.available || running;
    const nextTier = WORLD_BOSS_RULES.rewardTiers[reward.earnedTier + 1] ?? null;
    elements.worldBossRewardText.textContent = snapshot.resultsOpen
      ? current.attempts === 0
        ? '미참여 · 보상 없음'
        : reward.available
          ? `${reward.defeated ? '성공' : '실패'} +${number.format(reward.points)} P · 추가 드롭 판정`
          : '보상 수령 완료'
      : current.attempts === 0
        ? `${kstSlotLabel(snapshot.raidEndsAt)} 결과 공개 · 성공 최대 ${number.format(WORLD_BOSS_RULES.rewardTiers.at(-1).points)}P`
        : nextTier
          ? `현재 성공 ${number.format(WORLD_BOSS_RULES.rewardTiers[reward.earnedTier].points)}P · 다음 ${nextTier.label}`
          : `성공 ${number.format(reward.successPoints)}P 단계 달성 · 결과 대기`;
    renderParty();
    renderRanking(current.totalDamage);
    renderRecent(current.lastDamage);
    elements.worldBossScreen?.setAttribute('data-boss-status', status);
    window.lucide?.createIcons();
  }

  function flashAttack(event, count) {
    displayedDamage += event.damage;
    elements.worldBossAttemptDamage.textContent = number.format(displayedDamage);
    const card = elements.worldBossParty.querySelector(`[data-worldboss-card="${event.cardIndex}"]`);
    card?.classList.add('attacking');
    window.setTimeout(() => card?.classList.remove('attacking'), 150);
    elements.worldBossCore.classList.remove('hit');
    void elements.worldBossCore.offsetWidth;
    elements.worldBossCore.classList.add('hit');
    if (count % 5 === 0) {
      const damage = document.createElement('b');
      damage.className = `worldboss-damage${event.critical ? ' critical' : ''}`;
      damage.textContent = event.critical ? `CRIT ${number.format(event.damage)}` : number.format(event.damage);
      elements.worldBossCore.append(damage);
      damage.addEventListener('animationend', () => damage.remove(), { once: true });
    }
  }

  async function startBattle() {
    if (running) return;
    const now = clock.now();
    const current = progress(now);
    const snapshot = getWorldBossSnapshot(current, now);
    if (!snapshot.active) return showToast('현재 월드보스가 출현하지 않음');
    if (current.attempts >= WORLD_BOSS_RULES.maxAttempts) return showToast('월드보스 도전 3회 완료');
    if (!snapshot.canStartAttempt) return showToast('남은 시간이 부족해 교전 불가');
    const formation = getFormation();
    if (formation.length !== 5) return showToast('출전 카드 5장 편성 필요');

    running = true;
    displayedDamage = 0;
    const token = ++sequence;
    const result = simulateWorldBossAttempt(formation, getBonuses(), current.attempts + 1, current.eventId);
    render(now);
    elements.worldBossCore.classList.add('engaged');
    let previousAt = 0;
    let attackCount = 0;
    for (const event of result.events) {
      if (event.type !== 'attack') continue;
      await wait((event.at - previousAt) * 80);
      if (!active || token !== sequence) return;
      previousAt = event.at;
      attackCount += 1;
      flashAttack(event, attackCount);
    }
    await wait(260);
    if (!active || token !== sequence) return;

    if (serverCommands) {
      const response = await serverCommands.attackWorldBoss({ eventId: current.eventId });
      running = false;
      elements.worldBossCore.classList.remove('engaged');
      render();
      if (!response?.ok) return showToast('월드보스 공격 저장 실패');
      return showToast(`월드보스 피해 ${number.format(response.result?.damage ?? result.totalDamage)}`);
    }

    const state = getState();
    let recordedProgress;
    try {
      recordedProgress = recordWorldBossAttempt(current, result.totalDamage, clock.now());
    } catch {
      running = false;
      elements.worldBossCore.classList.remove('engaged');
      render();
      return showToast('회차가 종료되어 전투가 무효 처리됨');
    }
    state.worldBoss = recordedProgress;
    state.cardProgress = applyCardExperience(state.cardProgress, formation, WORLD_BOSS_RULES.cardExpPerAttempt);
    running = false;
    elements.worldBossCore.classList.remove('engaged');
    persist('attackWorldBoss');
    render();
    showToast(`월드보스 피해 ${number.format(result.totalDamage)} · 카드 EXP +${WORLD_BOSS_RULES.cardExpPerAttempt}`);
  }

  async function claimReward() {
    if (serverCommands) {
      const current = progress();
      const response = await serverCommands.claimWorldBossReward({ eventId: current.eventId });
      if (!response?.ok) return showToast('월드보스 보상 수령 실패');
      render();
      return showToast(`월드보스 보상 +${number.format(response.result?.points ?? 0)}P`);
    }
    const state = getState();
    const claimed = claimWorldBossReward(progress(), clock.now());
    if (!claimed.reward.available) return showToast('결과 공개 시간에만 보상 수령 가능');
    const bonusDrop = rollWorldBossBonusDrop(claimed.reward.defeated, random);
    state.worldBoss = claimed.progress;
    state.points += claimed.reward.points;
    state.supportItems = grantBonusDrop(state.supportItems, bonusDrop);
    persist('claimWorldBossReward');
    render();
    showToast([
      `월드보스 ${claimed.reward.defeated ? '성공' : '실패'} 보상 +${number.format(claimed.reward.points)} P`,
      bonusDropText(bonusDrop),
    ].filter(Boolean).join(' · '));
  }

  function tick() {
    if (!active) return;
    const now = clock.now();
    if (running) {
      const snapshot = getWorldBossSnapshot(progress(now), now);
      elements.worldBossTimer.textContent = formatDuration(snapshot.remainingSeconds);
      return;
    }
    render(now);
  }

  function setActive(value) {
    active = value;
    if (!active && running) {
      sequence += 1;
      running = false;
      elements.worldBossCore.classList.remove('engaged');
    }
    if (active) render();
  }

  elements.worldBossAttackButton.addEventListener('click', startBattle);
  elements.worldBossRewardButton.addEventListener('click', claimReward);
  return { render, tick, setActive };
}
