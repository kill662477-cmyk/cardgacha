import { escapeHtml } from './html.js';
import { guildLevelFor } from './config.js';
import { EMBLEM_GLYPHS, emblemMarkup } from './guild-emblem.js';

const number = new Intl.NumberFormat('ko-KR');

const ROLE_LABELS = Object.freeze({ owner: '길드장', officer: '부길드장', member: '길드원' });


function formatDate(ms) {
  if (!Number.isFinite(ms)) return '-';
  const date = new Date(ms);
  return `${date.getMonth() + 1}/${date.getDate()}`;
}

function relativeDays(ms) {
  if (!Number.isFinite(ms)) return '기록 없음';
  const days = Math.floor((Date.now() - ms) / 86_400_000);
  if (days <= 0) return '오늘';
  if (days === 1) return '어제';
  return `${days}일 전`;
}

export function createGuildController({ getState, gameService, serverCommands = null, showToast }) {
  const elements = Object.fromEntries([
    'guildHome', 'guildBrowse', 'guildEmblem', 'guildTagLine', 'guildName', 'guildMeta',
    'guildShowBrowse', 'guildShowHome',
    'guildActions', 'guildNotice', 'guildRequestsBox', 'guildRequestCount', 'guildRequestList',
    'guildMemberCount', 'guildMemberList', 'guildPenalty', 'guildCreateBox', 'guildCreateForm',
    'guildCreateName', 'guildCreateTag', 'guildEmblemPicker', 'guildList',
    'guildWeeklyBox', 'guildWeeklyClaim', 'guildWeeklyList', 'guildWeeklyNote',
    'guildRaidBox', 'guildRaidPhase', 'guildRaidNote', 'guildRaidHpBar',
    'guildRaidAttack', 'guildRaidClaim', 'guildRaidParticipants',
  ].map((id) => [id, document.getElementById(id)]));

  let guildState = null;
  let raidState = null;
  let selectedEmblem = 'shield';
  // 기여가 낮은 길드원을 바로 찾을 수 있도록 오름차순 정렬을 제공한다(PDB-16 2.6).
  let memberSort = 'role';
  let loading = false;

  const isRemote = Boolean(serverCommands);
  const myUserId = () => guildState?.membership?.userId ?? null;

  async function load() {
    if (!isRemote) {
      // 로컬 테스트 프로필에는 서버 길드 상태가 없다. 화면 골격만 보여 준다.
      guildState = null;
      render();
      return;
    }
    if (loading) return;
    loading = true;
    try {
      const [state, raid] = await Promise.all([
        gameService.getGuildState(),
        gameService.getGuildRaidStatus?.() ?? Promise.resolve(null),
      ]);
      guildState = state?.ok === false ? null : state;
      raidState = raid?.ok === false ? null : raid;
    } catch {
      guildState = null;
      raidState = null;
    } finally {
      loading = false;
      render();
    }
  }

  function renderEmblemPicker(emblems) {
    if (!elements.guildEmblemPicker) return;
    const list = Array.isArray(emblems) && emblems.length
      ? emblems
      : Object.keys(EMBLEM_GLYPHS).map((key) => ({ key, label: key }));
    elements.guildEmblemPicker.innerHTML = list.map(({ key, label }) => `
      <button type="button" class="guild-emblem-option${key === selectedEmblem ? ' selected' : ''}"
        data-emblem="${escapeHtml(key)}" title="${escapeHtml(label ?? key)}">${emblemMarkup(key, 'guild-emblem-option-mark')}</button>
    `).join('');
  }

  function renderMembers(members) {
    let rows = Array.isArray(members) ? [...members] : [];
    if (memberSort === 'gpAsc') rows.sort((a, b) => (a.weeklyGp ?? 0) - (b.weeklyGp ?? 0));
    else if (memberSort === 'gpDesc') rows.sort((a, b) => (b.weeklyGp ?? 0) - (a.weeklyGp ?? 0));
    elements.guildMemberCount.textContent = number.format(rows.length);
    const canManage = ['owner', 'officer'].includes(guildState?.membership?.role);
    const isOwner = guildState?.membership?.role === 'owner';
    elements.guildMemberList.innerHTML = rows.map((m) => {
      const manageable = canManage && m.role !== 'owner' && !(m.role === 'officer' && !isOwner);
      return `
      <li class="guild-member">
        <div class="guild-member-main">
          <strong>${escapeHtml(m.nickname ?? '-')}</strong>
          <span class="guild-role guild-role-${escapeHtml(m.role)}">${ROLE_LABELS[m.role] ?? m.role}</span>
        </div>
        <div class="guild-member-stats">
          <span>주간 ${number.format(m.weeklyGp ?? 0)} GP</span>
          <span>누적 ${number.format(m.totalGp ?? 0)}</span>
          <span>가입 ${formatDate(m.joinedAt)}</span>
          <span>활동 ${relativeDays(m.lastContributedAt)}</span>
        </div>
        ${manageable ? `<div class="guild-member-actions">
          ${isOwner ? `<button type="button" data-guild-role="${escapeHtml(m.userId)}" data-role-next="${m.role === 'officer' ? 'member' : 'officer'}">${m.role === 'officer' ? '부길드장 해임' : '부길드장 임명'}</button>` : ''}
          <button type="button" class="danger" data-guild-kick="${escapeHtml(m.userId)}">추방</button>
        </div>` : ''}
      </li>`;
    }).join('') || '<li class="guild-empty">길드원이 없습니다</li>';
  }

  function renderRaid() {
    if (!elements.guildRaidBox) return;
    const raid = raidState?.raid;
    if (!raid) {
      elements.guildRaidBox.hidden = true;
      return;
    }
    elements.guildRaidBox.hidden = false;
    const active = Boolean(raidState.active);
    const resultsOpen = Boolean(raidState.resultsOpen);
    const me = raidState.me ?? { attempts: 0, claimed: false };
    const ratio = raid.maxHp > 0 ? Math.max(0, Math.min(100, (raid.currentHp / raid.maxHp) * 100)) : 0;
    elements.guildRaidHpBar.style.width = `${ratio}%`;
    elements.guildRaidPhase.textContent = raid.defeated ? '처치 성공'
      : active ? '전투 중' : resultsOpen ? '결과 공개' : '대기';
    elements.guildRaidNote.textContent =
      `${number.format(raid.currentHp)} / ${number.format(raid.maxHp)}`
      + ` · 활동 길드원 ${number.format(raid.activeMemberCount ?? 0)}명 기준`
      + ` · 내 공격 ${me.attempts ?? 0}/3`;

    elements.guildRaidAttack.hidden = !(active && (me.attempts ?? 0) < 3);
    // 성공하면 미참여자도 받을 수 있고, 실패하면 참여자만 받을 수 있다.
    const claimable = resultsOpen && !me.claimed && (raid.defeated || (me.attempts ?? 0) > 0);
    elements.guildRaidClaim.hidden = !claimable;

    const rows = Array.isArray(raidState.participants) ? raidState.participants : [];
    elements.guildRaidParticipants.innerHTML = rows.map((p) => `
      <li class="guild-raid-participant${p.attempts > 0 ? '' : ' absent'}">
        <strong>${escapeHtml(p.nickname ?? '-')}</strong>
        <span>${p.attempts > 0 ? `${p.attempts}/3 · ${number.format(p.totalDamage)}` : '미참여'}</span>
      </li>`).join('') || '<li class="guild-empty">참여 기록이 없습니다</li>';
  }

  function renderWeekly(weekly) {
    if (!elements.guildWeeklyBox) return;
    if (!weekly || !Array.isArray(weekly.goals) || !weekly.goals.length) {
      elements.guildWeeklyBox.hidden = true;
      return;
    }
    elements.guildWeeklyBox.hidden = false;
    elements.guildWeeklyList.innerHTML = weekly.goals.map((g) => {
      const ratio = g.target > 0 ? Math.min(100, Math.round((g.progress / g.target) * 100)) : 0;
      return `<li class="guild-weekly-goal${g.complete ? ' complete' : ''}">
        <div class="guild-weekly-label"><strong>${escapeHtml(g.label)}</strong>
          <span>${number.format(g.progress)} / ${number.format(g.target)}</span></div>
        <div class="guild-weekly-bar"><i style="width:${ratio}%"></i></div>
        <small>1인 최대 ${number.format(g.memberCap)}회까지 집계</small>
      </li>`;
    }).join('');
    // 달성했고 아직 안 받았을 때만 수령 버튼을 노출한다.
    const claimable = Boolean(weekly.allComplete) && !weekly.claimed;
    elements.guildWeeklyClaim.hidden = !claimable;
    elements.guildWeeklyNote.textContent = weekly.claimed
      ? '이번 주 보상을 받았습니다 · 매주 월요일 초기화'
      : (weekly.allComplete ? '목표 달성! 보상을 받으세요' : '길드원 모두가 함께 채웁니다 · 매주 월요일 초기화');
  }

  function renderSortControls() {
    const head = document.querySelector('.guild-members-head');
    if (!head) return;
    let box = head.querySelector('.guild-sort');
    if (!box) {
      box = document.createElement('div');
      box.className = 'guild-sort';
      head.appendChild(box);
    }
    const options = [['role', '역할순'], ['gpAsc', '기여 낮은순'], ['gpDesc', '기여 높은순']];
    box.innerHTML = options.map(([key, label]) =>
      `<button type="button" data-guild-sort="${key}"${key === memberSort ? ' class="selected"' : ''}>${label}</button>`).join('');
  }

  function renderRequests(requests) {
    const rows = Array.isArray(requests) ? requests : null;
    if (!rows) {
      elements.guildRequestsBox.hidden = true;
      return;
    }
    elements.guildRequestsBox.hidden = false;
    elements.guildRequestCount.textContent = number.format(rows.length);
    elements.guildRequestList.innerHTML = rows.map((r) => `
      <li class="guild-request">
        <strong>${escapeHtml(r.nickname ?? '-')}</strong>
        <div>
          <button type="button" data-guild-approve="${escapeHtml(r.userId)}">승인</button>
          <button type="button" class="danger" data-guild-reject="${escapeHtml(r.userId)}">거절</button>
        </div>
      </li>`).join('') || '<li class="guild-empty">대기 중인 신청이 없습니다</li>';
  }

  // 소속 길드가 있을 때 'home'(내 길드) / 'browse'(다른 길드 목록) 중 무엇을 볼지.
  // 무소속이면 항상 browse 이므로 이 값은 무시된다.
  let guildView = 'home';

  function renderHome() {
    const guild = guildState.guild;
    const role = guildState.membership?.role;
    elements.guildHome.hidden = false;
    elements.guildBrowse.hidden = true;
    elements.guildEmblem.innerHTML = emblemMarkup(guild.emblem, 'guild-emblem-mark');
    elements.guildTagLine.textContent = guild.tag ? `[${guild.tag}] GUILD` : 'GUILD';
    elements.guildName.textContent = guild.name ?? '-';
    const tier = guildLevelFor(guild.totalGp ?? 0);
    const buffs = [
      tier.atk ? `공격 +${(tier.atk * 100).toFixed(0)}%` : null,
      tier.hp ? `체력 +${(tier.hp * 100).toFixed(0)}%` : null,
      tier.def ? `방어 +${(tier.def * 100).toFixed(0)}%` : null,
      tier.points ? `포인트 +${(tier.points * 100).toFixed(0)}%` : null,
    ].filter(Boolean);
    elements.guildMeta.textContent =
      `Lv.${guild.level} · ${number.format(guild.memberCount ?? 0)}/${guild.memberLimit}명 · ${ROLE_LABELS[role] ?? '길드원'}`
      + ` · 누적 ${number.format(guild.totalGp ?? 0)} GP`
      + (buffs.length ? ` · ${buffs.join(' / ')}` : ' · 버프 없음');
    if (guild.notice) {
      elements.guildNotice.hidden = false;
      elements.guildNotice.textContent = guild.notice;
    } else {
      elements.guildNotice.hidden = true;
    }

    const actions = [];
    if (role === 'owner') {
      // 버튼 하나가 눌릴 때마다 글자가 바뀌면 "지금 상태"인지 "누르면 될 상태"인지 헷갈린다.
      // 두 모드를 나란히 놓고 현재 것을 활성 표시하는 토글로 보여 준다.
      const mode = guild.joinMode === 'auto' ? 'auto' : 'approval';
      actions.push(`<div class="guild-joinmode" role="group" aria-label="가입 방식">
        <span>가입</span>
        <button type="button" data-guild-joinmode="approval"${mode === 'approval' ? ' class="selected" aria-pressed="true"' : ''}>승인제</button>
        <button type="button" data-guild-joinmode="auto"${mode === 'auto' ? ' class="selected" aria-pressed="true"' : ''}>자동승인</button>
      </div>`);
      actions.push('<button type="button" class="danger" data-guild-disband>길드 해산</button>');
    } else {
      actions.push('<button type="button" class="danger" data-guild-leave>길드 탈퇴</button>');
    }
    elements.guildActions.innerHTML = actions.join('');

    renderRaid();
    renderWeekly(guildState.weekly);
    renderRequests(guildState.joinRequests);
    renderMembers(guildState.members);
    renderSortControls();
  }

  // isMember 면 "구경만" 하는 상태다. 가입/생성 수단을 감추고 돌아가기 버튼을 띄운다.
  function renderBrowse(isMember = false) {
    elements.guildHome.hidden = true;
    elements.guildBrowse.hidden = false;
    if (elements.guildShowHome) elements.guildShowHome.hidden = !isMember;
    if (elements.guildWeeklyBox) elements.guildWeeklyBox.hidden = true;
    if (elements.guildRaidBox) elements.guildRaidBox.hidden = true;

    const penaltyUntil = guildState?.penaltyUntil;
    if (isMember) {
      elements.guildPenalty.hidden = true;
    } else if (Number.isFinite(penaltyUntil) && penaltyUntil > Date.now()) {
      const hours = Math.ceil((penaltyUntil - Date.now()) / 3_600_000);
      elements.guildPenalty.hidden = false;
      elements.guildPenalty.textContent = `길드 탈퇴 후 재가입 제한 중입니다 (약 ${hours}시간 남음)`;
    } else {
      elements.guildPenalty.hidden = true;
    }

    const isStreamer = !isMember && Boolean(getState?.()?.isStreamer ?? guildState?.canCreateGuild);
    elements.guildCreateBox.hidden = !isStreamer;
    if (isStreamer) renderEmblemPicker(guildState?.emblems);

    const guilds = Array.isArray(guildState?.guilds) ? guildState.guilds : [];
    const myRequests = new Set((guildState?.myRequests ?? []).map((r) => r.guildId));
    elements.guildList.innerHTML = guilds.map((g) => {
      const full = (g.memberCount ?? 0) >= g.memberLimit;
      const pending = myRequests.has(g.guildId);
      const mine = isMember && g.guildId === guildState?.guild?.guildId;
      return `
      <li class="guild-list-item">
        <div class="guild-list-emblem">${emblemMarkup(g.emblem, 'guild-list-emblem-mark')}</div>
        <div class="guild-list-main">
          <strong>${escapeHtml(g.name ?? '-')}${g.tag ? ` <em>[${escapeHtml(g.tag)}]</em>` : ''}</strong>
          <small>Lv.${g.level} · ${number.format(g.memberCount ?? 0)}/${g.memberLimit}명 · ${escapeHtml(g.ownerNickname ?? '')}</small>
        </div>
        ${mine
          ? '<span class="guild-list-mine">내 길드</span>'
          : isMember
            ? ''
            : pending
              ? `<button type="button" data-guild-cancel="${escapeHtml(g.guildId)}">신청 취소</button>`
              : `<button type="button" data-guild-join="${escapeHtml(g.guildId)}" ${full ? 'disabled' : ''}>${full ? '정원 마감' : (g.joinMode === 'auto' ? '즉시 가입' : '가입 신청')}</button>`}
      </li>`;
    }).join('') || '<li class="guild-empty">아직 만들어진 길드가 없습니다</li>';
  }

  function render() {
    if (!elements.guildHome || !elements.guildBrowse) return;
    if (!isRemote) {
      elements.guildHome.hidden = true;
      elements.guildBrowse.hidden = false;
      elements.guildPenalty.hidden = true;
      elements.guildCreateBox.hidden = true;
      elements.guildList.innerHTML = '<li class="guild-empty">길드는 서버 연결 후 이용할 수 있습니다</li>';
      return;
    }
    const isMember = Boolean(guildState?.guild && guildState?.membership);
    if (!isMember) guildView = 'home';
    if (isMember && guildView === 'home') renderHome();
    else renderBrowse(isMember);
  }

  async function run(operation) {
    if (!serverCommands) return;
    try {
      const result = await operation();
      if (result?.ok === false) {
        showToast?.(result.message ?? '요청을 처리하지 못했습니다');
        return;
      }
      await load();
    } catch (error) {
      showToast?.(error?.message ?? '요청을 처리하지 못했습니다');
    }
  }

  function bindEvents() {
    // 소속 길드가 있어도 다른 길드 현황을 볼 수 있게 두 화면을 오간다.
    // 서버는 가입 여부와 무관하게 목록을 내려주므로 추가 요청이 필요 없다.
    elements.guildShowBrowse?.addEventListener('click', () => {
      guildView = 'browse';
      render();
    });
    elements.guildShowHome?.addEventListener('click', () => {
      guildView = 'home';
      render();
    });

    elements.guildCreateForm?.addEventListener('submit', (event) => {
      event.preventDefault();
      const name = elements.guildCreateName.value.trim();
      if (name.length < 2) {
        showToast?.('길드 이름은 2자 이상이어야 합니다');
        return;
      }
      void run(() => serverCommands.createGuild({
        name, tag: elements.guildCreateTag.value.trim() || null, emblem: selectedEmblem,
      }));
    });

    elements.guildEmblemPicker?.addEventListener('click', (event) => {
      const key = event.target.closest('[data-emblem]')?.dataset.emblem;
      if (!key) return;
      selectedEmblem = key;
      renderEmblemPicker(guildState?.emblems);
    });

    document.getElementById('guildScreen')?.addEventListener('click', (event) => {
      const target = event.target.closest('button');
      if (!target) return;
      const { guildJoin, guildCancel, guildKick, guildApprove, guildReject, guildRole, guildJoinmode, guildSort } = target.dataset;
      if (guildSort) { memberSort = guildSort; renderMembers(guildState?.members); renderSortControls(); return; }
      if (guildJoin) void run(() => serverCommands.requestJoinGuild({ guildId: guildJoin }));
      else if (guildCancel) void run(() => serverCommands.cancelJoinRequest({ guildId: guildCancel }));
      else if (guildKick) void run(() => serverCommands.kickGuildMember({ targetUserId: guildKick }));
      else if (guildApprove) void run(() => serverCommands.resolveJoinRequest({ targetUserId: guildApprove, approve: true }));
      else if (guildReject) void run(() => serverCommands.resolveJoinRequest({ targetUserId: guildReject, approve: false }));
      else if (guildRole) void run(() => serverCommands.setGuildMemberRole({ targetUserId: guildRole, role: target.dataset.roleNext }));
      else if (guildJoinmode) {
        if (guildJoinmode === (guildState?.guild?.joinMode ?? 'approval')) return;
        void run(() => serverCommands.updateGuildSettings({ notice: guildState?.guild?.notice ?? '', joinMode: guildJoinmode }));
      }
      else if (target.id === 'guildRaidAttack') void run(() => serverCommands.attackGuildRaid());
      else if (target.id === 'guildRaidClaim') void run(() => serverCommands.claimGuildRaidReward());
      else if (target.id === 'guildWeeklyClaim') void run(() => serverCommands.claimGuildWeeklyReward());
      else if (target.hasAttribute('data-guild-leave')) void run(() => serverCommands.leaveGuild());
      else if (target.hasAttribute('data-guild-disband')) {
        if (window.confirm('길드를 해산하면 모든 길드원이 탈퇴 처리됩니다. 계속할까요?')) {
          void run(() => serverCommands.disbandGuild());
        }
      }
    });
  }

  bindEvents();
  render();

  return { load, render, get state() { return guildState; } };
}
