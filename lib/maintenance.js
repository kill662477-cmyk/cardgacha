const MAINTENANCE_AT = '2026-07-17T14:59:00.000Z'; // 2026-07-17 23:59 KST

function isMaintenance(now = Date.now()) {
  return process.env.MAINTENANCE_FORCE === '1' || now >= Date.parse(MAINTENANCE_AT);
}

function rejectDuringMaintenance(res, sendJson, now = Date.now()) {
  if (!isMaintenance(now)) return false;
  sendJson(res, 503, {
    error: '대규모 리뉴얼 공사 중입니다.',
    maintenance: true,
    maintenanceAt: MAINTENANCE_AT,
  });
  return true;
}

module.exports = { MAINTENANCE_AT, isMaintenance, rejectDuringMaintenance };
