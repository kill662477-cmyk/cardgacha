import { RARITIES, SUPPORT_ITEMS } from './config.js';
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
import { getWorldBossTier, kstSlotLabel, worldBossHourFromEventId } from './worldboss-schedule.js';
import { bonusDropText, grantBonusDrop, rollWorldBossBonusDrop, rollWorldBossDestructionGuardDrop } from './bonus-loot.js';

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

export function createWorldBossController({ getState, getFormation, getBonuses, persist, showToast, clock, random, serverCommands = null, onRewardAvailability = null }) {
  const elements = Object.fromEntries([
    'worldBossScreen', 'worldBossEventState', 'worldBossTimer', 'worldBossClockLabel', 'worldBossNextSlot',
    'worldBossSchedule', 'worldBossPhase', 'worldBossTitle', 'worldBossName',
    'worldBossHpBar', 'worldBossHpText', 'worldBossCore', 'worldBossCoreName', 'worldBossCorePhase', 'worldBossAttemptDamage',
    'worldBossParty', 'worldBossParticipants', 'worldBossBestDamage', 'worldBossTotalDamage',
    'worldBossAttempts', 'worldBossPercentile', 'worldBossAttackButton', 'worldBossRewardButton',
    'worldBossRewardText', 'worldBossRanking', 'worldBossRecent',
  ].map((id) => [id, document.getElementById(id)]));

  let active = false;
  let running = false;
  let sequence = 0;
  let displayedDamage = 0;
  let serverStatus = null;
  let serverStatusFetchedAt = 0;
  let serverStatusRequest = null;
  let unsubscribeWorldBoss = null;

  function imagePath(card) {
    return `assets/cards/${encodeURIComponent(card.file)}`;
  }

  function progress(now = clock.now()) {
    const state = getState();
    state.worldBoss = normalizeWorldBossProgress(state.worldBoss, now);
    return state.worldBoss;
  }

  function serverProgress() {
    const event = serverStatus?.event;
    const player = serverStatus?.player;
    if (!event || !player) return null;
    return {
      eventId: event.eventId,
      startedAt: event.startsAt,
      endsAt: event.endsAt,
      attempts: Number(player.attempts ?? 0),
      bestDamage: Number(player.bestDamage ?? 0),
      totalDamage: Number(player.totalDamage ?? 0),
      claimedTier: Number(player.claimedTier ?? -1),
      lastDamage: Number(player.lastDamage ?? 0),
    };
  }

  async function refreshServerStatus(force = false) {
    if (!serverCommands?.getWorldBossStatus) return null;
    if (!force && serverStatus && clock.now() - serverStatusFetchedAt < 10_000) return serverStatus;
    if (serverStatusRequest) return serverStatusRequest;
    serverStatusRequest = serverCommands.getWorldBossStatus()
      .then((response) => {
        if (response?.ok === false || !response?.status) return serverStatus;
        serverStatus = response.status;
        serverStatusFetchedAt = clock.now();
        const current = serverProgress();
        if (current) getState().worldBoss = current;
        if (active) render();
        return serverStatus;
      })
      .finally(() => { serverStatusRequest = null; });
    return serverStatusRequest;
  }

  // Background reward-availability check, independent of whether the world boss
  // screen is open. Lets the nav badge warn players who never revisit the screen
  // before the 30-minute claim window closes (claim is manual by design).
  async function checkRewardAvailability() {
    if (!serverCommands?.getWorldBossStatus) return;
    await refreshServerStatus();
    const event = serverStatus?.event;
    const current = serverProgress();
    if (!event || !current) return;
    const earnedTier = earnedRewardTier(current.totalDamage);
    onRewardAvailability?.(event.resultsOpen && current.attempts > 0 && current.claimedTier < earnedTier);
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

  function earnedRewardTier(totalDamage) {
    let tier = -1;
    WORLD_BOSS_RULES.rewardTiers.forEach((rule, index) => {
      if (totalDamage >= rule.damage) tier = index;
    });
    return tier;
  }

  function applyBossTier(eventId) {
    const tier = getWorldBossTier(eventId);
    const hour = worldBossHourFromEventId(eventId);
    elements.worldBossCore.dataset.slotHour = String(hour);
    elements.worldBossTitle.textContent = tier.title;
    elements.worldBossName.textContent = tier.name;
    elements.worldBossCoreName.textContent = tier.name;
    elements.worldBossSchedule.textContent = `매일 ${WORLD_BOSS_RULES.scheduleHours.join('·')}시 KST · ${hour}시 난이도 ×${tier.difficultyMultiplier.toFixed(3)} · 처치 성공 시 파괴 차단제 ${Math.round((tier.clearDestructionGuardRate ?? 0) * 100)}% 확률 지급`;
  }

  function renderServerStatus(now) {
    const event = serverStatus?.event;
    const current = serverProgress();
    if (!event || !current) return false;
    const status = event.resultsOpen
      ? event.defeated ? 'result-success' : 'result-failure'
      : event.active ? 'live' : event.defeated ? 'closed' : 'standby';
    const nextStartsAt = Number(serverStatus.schedule?.nextSlot?.startsAt ?? event.startsAt);
    const remainingMs = status === 'standby'
      ? nextStartsAt - now
      : (event.resultsOpen ? event.endsAt : event.raidEndsAt) - now;
    const hpRatio = event.maxHp > 0 ? event.currentHp / event.maxHp : 0;
    const earnedTier = earnedRewardTier(current.totalDamage);
    const rewardRule = earnedTier >= 0 ? WORLD_BOSS_RULES.rewardTiers[earnedTier] : null;
    const rewardPoints = rewardRule ? (event.defeated ? rewardRule.points : rewardRule.failurePoints) : 0;
    const rewardAvailable = event.resultsOpen && current.attempts > 0 && current.claimedTier < earnedTier;
    onRewardAvailability?.(rewardAvailable);
    const leaderboard = Array.isArray(serverStatus.leaderboard) ? serverStatus.leaderboard : [];

    elements.worldBossEventState.textContent = event.resultsOpen
      ? event.defeated ? 'RAID CLEAR · RESULT' : 'RAID FAILED · RESULT'
      : event.active ? 'SERVER RAID LIVE' : event.defeated ? 'BOSS DEFEATED' : 'NEXT RAID STANDBY';
    elements.worldBossTimer.textContent = formatDuration(remainingMs / 1000);
    elements.worldBossClockLabel.textContent = status === 'standby' ? '다음 출현까지' : event.resultsOpen ? '결과 종료까지' : '레이드 종료까지';
    applyBossTier(event.eventId);
    if (elements.worldBossNextSlot) {
      elements.worldBossNextSlot.hidden = status !== 'standby';
      elements.worldBossNextSlot.textContent = status === 'standby' ? `다음 출현 ${kstSlotLabel(nextStartsAt)} KST` : '';
    }
    elements.worldBossPhase.textContent = `PHASE ${event.phase}`;
    elements.worldBossHpBar.style.width = `${Math.max(0, Math.min(100, hpRatio * 100))}%`;
    elements.worldBossHpText.textContent = `${number.format(event.currentHp)} / ${number.format(event.maxHp)}`;
    elements.worldBossCore.dataset.phase = event.phase;
    elements.worldBossCorePhase.textContent = `PHASE ${event.phase} · ${event.phase === 1 ? '악성 신호 활성' : event.phase === 2 ? '과부하 폭주' : '코어 붕괴 임계'}`;
    if (!running) displayedDamage = current.lastDamage;
    elements.worldBossAttemptDamage.textContent = number.format(displayedDamage);
    elements.worldBossParticipants.textContent = number.format(event.participants ?? 0);
    elements.worldBossBestDamage.textContent = number.format(current.bestDamage);
    elements.worldBossTotalDamage.textContent = number.format(current.totalDamage);
    elements.worldBossAttempts.textContent = `${Math.max(0, WORLD_BOSS_RULES.maxAttempts - current.attempts)} / ${WORLD_BOSS_RULES.maxAttempts}`;
    const rank = Number(serverStatus.player?.rank ?? 0);
    elements.worldBossPercentile.textContent = rank > 0 ? `${number.format(rank)}위 / ${number.format(event.participants ?? 0)}명` : '미참여';
    const hasEnergy = Number(getState().actionEnergy ?? 0) >= WORLD_BOSS_RULES.attackEnergyCost;
    elements.worldBossAttackButton.disabled = running || !serverStatus.player?.canAttack || !hasEnergy;
    elements.worldBossAttackButton.querySelector('span').textContent = running
      ? '교전 데이터 전송 중'
      : event.resultsOpen ? event.defeated ? '레이드 성공' : '레이드 실패'
        : event.active ? !hasEnergy ? '행동력 부족' : serverStatus.player?.canAttack ? '보스 교전 시작' : '교전 시작 불가' : '월드보스 대기 중';
    elements.worldBossRewardButton.disabled = !rewardAvailable || running;
    elements.worldBossRewardText.textContent = event.resultsOpen
      ? current.attempts === 0 ? '미참여 · 보상 없음'
        : rewardAvailable ? `${event.defeated ? '성공' : '실패'} +${number.format(rewardPoints)} P · ${event.defeated ? `파괴 차단제 ${Math.round((getWorldBossTier(event.eventId).clearDestructionGuardRate ?? 0) * 100)}% 확률 추첨` : '추가 보상 추첨'}`
          : '보상 수령 완료'
      : current.attempts === 0 ? `${kstSlotLabel(event.raidEndsAt)} 결과 공개 · 성공 최대 ${number.format(WORLD_BOSS_RULES.rewardTiers.at(-1).points)}P`
        : `누적 피해 ${number.format(current.totalDamage)} · 결과 대기`;
    renderParty();
    elements.worldBossRanking.innerHTML = leaderboard.slice(0, 6).map((row) => `
      <li class="${row.nickname === getState().nickname ? 'mine' : ''}"><b>${row.rank}</b><span>${escapeHtml(row.nickname)}</span><strong>${number.format(row.damage)}</strong></li>`).join('');
    elements.worldBossRecent.innerHTML = leaderboard.slice(0, 3).map((row) => `<li><i></i><span>${escapeHtml(row.nickname)}</span><b>+${number.format(row.damage)}</b></li>`).join('');
    elements.worldBossScreen?.setAttribute('data-boss-status', status);
    window.lucide?.createIcons();
    return true;
  }

  function render(now = clock.now()) {
    if (serverCommands && renderServerStatus(now)) return;
    if (serverCommands) {
      elements.worldBossEventState.textContent = 'SERVER RAID SYNC';
      elements.worldBossAttackButton.disabled = true;
      elements.worldBossRewardButton.disabled = true;
      void refreshServerStatus();
      return;
    }
    const current = progress(now);
    const snapshot = getWorldBossSnapshot(current, now);
    const reward = getWorldBossReward(current, now);
    onRewardAvailability?.(reward.available);
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
    applyBossTier(current.eventId);
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
    const hasEnergy = Number(getState().actionEnergy ?? 0) >= WORLD_BOSS_RULES.attackEnergyCost;
    elements.worldBossAttackButton.disabled = running || !snapshot.canStartAttempt || !hasEnergy;
    elements.worldBossAttackButton.querySelector('span').textContent = running
      ? '교전 데이터 전송 중'
      : snapshot.resultsOpen ? snapshot.defeated ? '레이드 성공' : '레이드 실패'
        : !snapshot.active ? snapshot.defeated ? '결과 집계 중' : '월드보스 대기 중'
        : !hasEnergy ? '행동력 부족'
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
    if (serverCommands && !serverStatus) await refreshServerStatus(true);
    const current = serverCommands ? serverProgress() : progress(now);
    const snapshot = serverCommands ? serverStatus?.event : getWorldBossSnapshot(current, now);
    if (!current || !snapshot?.active) return showToast('현재 월드보스가 출현하지 않음');
    if (current.attempts >= WORLD_BOSS_RULES.maxAttempts) return showToast('월드보스 도전 3회 완료');
    if (serverCommands ? !serverStatus?.player?.canAttack : !snapshot.canStartAttempt) return showToast('남은 시간이 부족해 교전 불가');
    if (Number(getState().actionEnergy ?? 0) < WORLD_BOSS_RULES.attackEnergyCost) return showToast('행동력이 부족합니다.');
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
      await refreshServerStatus(true);
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
    state.actionEnergy -= WORLD_BOSS_RULES.attackEnergyCost;
    state.lastEnergyAt = clock.now();
    state.cardProgress = applyCardExperience(state.cardProgress, formation, WORLD_BOSS_RULES.cardExpPerAttempt);
    running = false;
    elements.worldBossCore.classList.remove('engaged');
    persist('attackWorldBoss');
    render();
    showToast(`월드보스 피해 ${number.format(result.totalDamage)} · 카드 EXP +${WORLD_BOSS_RULES.cardExpPerAttempt}`);
  }

  async function claimReward() {
    if (serverCommands) {
      if (!serverStatus) await refreshServerStatus(true);
      const current = serverProgress();
      if (!current) return showToast('월드보스 회차 정보 없음');
      const response = await serverCommands.claimWorldBossReward({ eventId: current.eventId });
      if (!response?.ok) return showToast('월드보스 보상 수령 실패');
      await refreshServerStatus(true);
      render();
      const bonusItemIds = Array.isArray(response.result?.bonusItemIds)
        ? response.result.bonusItemIds
        : [response.result?.bonusItemId].filter(Boolean);
      const bonusText = bonusItemIds.map((itemId) => SUPPORT_ITEMS[itemId]?.name ?? itemId).join(', ');
      return showToast(`월드보스 보상 +${number.format(response.result?.points ?? 0)}P${bonusText ? ` · 추가 획득 ${bonusText}` : ''}`);
    }
    const state = getState();
    const claimed = claimWorldBossReward(progress(), clock.now());
    if (!claimed.reward.available) return showToast('결과 공개 시간에만 보상 수령 가능');
    const bonusDrop = rollWorldBossBonusDrop(claimed.reward.defeated, random);
    const destructionGuardDrop = rollWorldBossDestructionGuardDrop(claimed.progress.eventId, claimed.reward.defeated, random);
    state.worldBoss = claimed.progress;
    state.points += claimed.reward.points;
    state.supportItems = grantBonusDrop(state.supportItems, bonusDrop);
    state.supportItems = grantBonusDrop(state.supportItems, destructionGuardDrop);
    persist('claimWorldBossReward');
    render();
    showToast([
      `월드보스 ${claimed.reward.defeated ? '성공' : '실패'} 보상 +${number.format(claimed.reward.points)} P`,
      bonusDropText(bonusDrop),
      bonusDropText(destructionGuardDrop),
    ].filter(Boolean).join(' · '));
  }

  function tick() {
    if (!active) return;
    const now = clock.now();
    if (serverCommands) {
      if (running && serverStatus?.event) {
        const remainingAt = serverStatus.event.resultsOpen ? serverStatus.event.endsAt : serverStatus.event.raidEndsAt;
        elements.worldBossTimer.textContent = formatDuration((remainingAt - now) / 1000);
      } else render(now);
      if (now - serverStatusFetchedAt >= 10_000) void refreshServerStatus();
      return;
    }
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
    if (active) {
      render();
      void refreshServerStatus(true);
      if (serverCommands?.subscribeWorldBoss && !unsubscribeWorldBoss) {
        unsubscribeWorldBoss = serverCommands.subscribeWorldBoss(() => { void refreshServerStatus(true); });
      }
    } else if (unsubscribeWorldBoss) {
      unsubscribeWorldBoss();
      unsubscribeWorldBoss = null;
    }
  }

  elements.worldBossAttackButton.addEventListener('click', startBattle);
  elements.worldBossRewardButton.addEventListener('click', claimReward);
  return { render, tick, setActive, checkRewardAvailability };
}
