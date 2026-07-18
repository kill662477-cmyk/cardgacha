// Deployment replaces these public values. Never put secret/service-role keys here.
globalThis.__CARD_GACHA_CONFIG__ = globalThis.__CARD_GACHA_CONFIG__ ?? {
  supabaseUrl: 'https://rljvzultuyiudhjjfotg.supabase.co',
  supabasePublishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJsanZ6dWx0dXlpdWRoampmb3RnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2NzUzNjUsImV4cCI6MjA5NzI1MTM2NX0.U2FYWE4AOfJS6utrXDvwhU4yUqNtDDKk75OM27IXXWU',
  // Maintenance toggle (Phase 1): true로 설정하면 app.js 로드 전에 점검 페이지로 가로채기.
  // 운영 토글 = 이 값을 수정 후 재배포. false로 두면 정상 동작.
  maintenance: true,
  maintenanceTitle: '시즌2 점검 중',
  maintenanceMessage: 'SOOP 숲 로그인 복구 작업을 진행하고 있습니다. 잠시 후 다시 접속해 주세요.',
  maintenanceCode: 'MAINTENANCE // SOOP AUTH RESTORE',
};

// 점검 모드: app.js 모듈 실행 전에 본문을 가리고 점검 오버레이를 노출한다.
// index.html에 <div id="maintenanceOverlay">가 없으면 인라인으로 최소 마크업을 만든다.
(function applyMaintenanceGuard() {
  if (typeof document === 'undefined') return;
  const config = globalThis.__CARD_GACHA_CONFIG__;
  if (!config || !config.maintenance) return;

  const injectOverlay = () => {
    if (document.getElementById('maintenanceOverlay')) return;
    const overlay = document.createElement('div');
    overlay.id = 'maintenanceOverlay';
    overlay.setAttribute('role', 'status');
    overlay.setAttribute('aria-live', 'polite');
    overlay.style.cssText = [
      'position:fixed', 'inset:0', 'z-index:9999',
      'display:flex', 'flex-direction:column', 'align-items:center', 'justify-content:center',
      'gap:18px', 'padding:32px', 'text-align:center',
      'background:radial-gradient(120% 120% at 50% 0%, #0c1310 0%, #050807 60%, #000 100%)',
      'color:#e8f2d0', 'font-family:system-ui,Segoe UI,Malgun Gothic,sans-serif',
    ].join(';');
    const title = config.maintenanceTitle ?? '점검 중';
    const message = config.maintenanceMessage ?? '잠시 후 다시 접속해 주세요.';
    const code = config.maintenanceCode ?? 'MAINTENANCE';
    overlay.innerHTML =
      '<div style="font-size:13px;letter-spacing:.32em;color:#7dd13f;font-weight:700">' + code + '</div>'
      + '<h1 style="margin:0;font-size:clamp(28px,6vw,52px);font-weight:800;letter-spacing:-.02em">' + title + '</h1>'
      + '<p style="margin:0;max-width:520px;font-size:16px;line-height:1.6;color:#9fb29a">' + message + '</p>'
      + '<button type="button" onclick="location.reload()" style="margin-top:8px;padding:12px 24px;border:1px solid #2a3a2a;background:#0f1612;color:#c8f52e;border-radius:10px;cursor:pointer;font-weight:600">새로고침</button>';
    document.body.appendChild(overlay);
  };

  const hideApp = () => {
    const shell = document.getElementById('gameShell');
    if (shell) shell.style.display = 'none';
    injectOverlay();
  };

  if (document.body) hideApp();
  else document.addEventListener('DOMContentLoaded', hideApp, { once: true });

  // app.js 모듈 실행 차단 신호. app.js는 init() 진입 전에 이 플래그를 확인한다.
  config.maintenanceActive = true;
})();
