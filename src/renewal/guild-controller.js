import { escapeHtml } from './html.js';
import { guildLevelFor } from './config.js';

const number = new Intl.NumberFormat('ko-KR');

const ROLE_LABELS = Object.freeze({ owner: '길드장', officer: '부길드장', member: '길드원' });

// 기본 엠블럼 8종의 표시용 기호. 실제 이미지 에셋이 준비되면
// assets/renewal/guild/emblems/<key>.png 를 우선 사용하도록 교체한다(PDB-16 7.2).
const EMBLEM_GLYPHS = Object.freeze({
  shield: '🛡', bolt: '⚡', star: '★', crown: '♛',
  flame: '🔥', blade: '⚔', hexcore: '⬢', signal: '📡',
});

function emblemGlyph(key) {
  return EMBLEM_GLYPHS[key] ?? EMBLEM_GLYPHS.shield;
}

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
    'guildActions', 'guildNotice', 'guildRequestsBox', 'guildRequestCount', 'guildRequestList',
    'guildMemberCount', 'guildMemberList', 'guildPenalty', 'guildCreateBox', 'guildCreateForm',
    'guildCreateName', 'guildCreateTag', 'guildEmblemPicker', 'guildList',
    'guildWeeklyBox', 'guildWeeklyClaim', 'guildWeeklyList', 'guildWeeklyNote',
  ].map((id) => [id, document.getElementById(id)]));

  let guildState = null;
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
      const result = await gameService.getGuildState();
      guildState = result?.ok === false ? null : result;
    } catch {
      guildState = null;
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
        data-emblem="${escapeHtml(key)}" title="${escapeHtml(label ?? key)}">${emblemGlyph(key)}</button>
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

  function renderHome() {
    const guild = guildState.guild;
    const role = guildState.membership?.role;
    elements.guildHome.hidden = false;
    elements.guildBrowse.hidden = true;
    elements.guildEmblem.textContent = emblemGlyph(guild.emblem);
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
      actions.push(`<button type="button" data-guild-joinmode="${guild.joinMode === 'auto' ? 'approval' : 'auto'}">
        가입 ${guild.joinMode === 'auto' ? '자동승인 켜짐' : '승인제'}</button>`);
      actions.push('<button type="button" class="danger" data-guild-disband>길드 해산</button>');
    } else {
      actions.push('<button type="button" class="danger" data-guild-leave>길드 탈퇴</button>');
    }
    elements.guildActions.innerHTML = actions.join('');

    renderWeekly(guildState.weekly);
    renderRequests(guildState.joinRequests);
    renderMembers(guildState.members);
    renderSortControls();
  }

  function renderBrowse() {
    elements.guildHome.hidden = true;
    elements.guildBrowse.hidden = false;
    if (elements.guildWeeklyBox) elements.guildWeeklyBox.hidden = true;

    const penaltyUntil = guildState?.penaltyUntil;
    if (Number.isFinite(penaltyUntil) && penaltyUntil > Date.now()) {
      const hours = Math.ceil((penaltyUntil - Date.now()) / 3_600_000);
      elements.guildPenalty.hidden = false;
      elements.guildPenalty.textContent = `길드 탈퇴 후 재가입 제한 중입니다 (약 ${hours}시간 남음)`;
    } else {
      elements.guildPenalty.hidden = true;
    }

    const isStreamer = Boolean(getState?.()?.isStreamer ?? guildState?.canCreateGuild);
    elements.guildCreateBox.hidden = !isStreamer;
    if (isStreamer) renderEmblemPicker(guildState?.emblems);

    const guilds = Array.isArray(guildState?.guilds) ? guildState.guilds : [];
    const myRequests = new Set((guildState?.myRequests ?? []).map((r) => r.guildId));
    elements.guildList.innerHTML = guilds.map((g) => {
      const full = (g.memberCount ?? 0) >= g.memberLimit;
      const pending = myRequests.has(g.guildId);
      return `
      <li class="guild-list-item">
        <div class="guild-list-emblem">${emblemGlyph(g.emblem)}</div>
        <div class="guild-list-main">
          <strong>${escapeHtml(g.name ?? '-')}${g.tag ? ` <em>[${escapeHtml(g.tag)}]</em>` : ''}</strong>
          <small>Lv.${g.level} · ${number.format(g.memberCount ?? 0)}/${g.memberLimit}명 · ${escapeHtml(g.ownerNickname ?? '')}</small>
        </div>
        ${pending
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
    if (guildState?.guild && guildState?.membership) renderHome();
    else renderBrowse();
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
      else if (guildJoinmode) void run(() => serverCommands.updateGuildSettings({ notice: guildState?.guild?.notice ?? '', joinMode: guildJoinmode }));
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
