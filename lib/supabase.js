/*
 * Supabase REST(PostgREST) 헬퍼. service_role 키로만 접근한다 (RLS 우회).
 * @supabase/supabase-js 의존성 없이 전역 fetch 만 사용 (Node 18+).
 * 절대 프론트로 노출되지 않는 서버리스 전용 코드.
 */
const { loadEnv } = require('./env');
loadEnv();

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SECRET_KEY;

if (!SUPABASE_URL) console.warn('[supabase] NEXT_PUBLIC_SUPABASE_URL 미설정');
if (!SERVICE_KEY) console.warn('[supabase] SERVICE_ROLE/SECRET 키 미설정');

const REST = `${SUPABASE_URL}/rest/v1`;

function headers(extra) {
  return Object.assign(
    {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
    },
    extra || {}
  );
}

async function sbFetch(url, opts) {
  const res = await fetch(url, opts);
  const text = await res.text();
  let body = null;
  if (text) {
    try { body = JSON.parse(text); } catch (e) { body = text; }
  }
  if (!res.ok) {
    const err = new Error(`Supabase ${res.status}: ${typeof body === 'string' ? body : JSON.stringify(body)}`);
    err.status = res.status;
    throw err;
  }
  return body;
}

// ---- users ----
async function getUserByKey(key) {
  const rows = await sbFetch(
    `${REST}/gacha_users?login_key=eq.${encodeURIComponent(key)}&select=*`,
    { headers: headers() }
  );
  return rows && rows[0] ? rows[0] : null;
}

async function insertUser(nickname, key) {
  const rows = await sbFetch(`${REST}/gacha_users`, {
    method: 'POST',
    headers: headers({ Prefer: 'return=representation' }),
    body: JSON.stringify({ nickname, login_key: key }),
  });
  return rows[0];
}

async function updateUser(id, patch) {
  const rows = await sbFetch(`${REST}/gacha_users?id=eq.${id}`, {
    method: 'PATCH',
    headers: headers({ Prefer: 'return=representation' }),
    body: JSON.stringify(patch),
  });
  return rows[0];
}

// ---- collection ----
async function getCollection(userId) {
  return sbFetch(
    `${REST}/gacha_collection?user_id=eq.${userId}&select=card_id,count,first_at`,
    { headers: headers() }
  );
}

async function getCollectionCounts(userId, cardIds) {
  if (!cardIds.length) return {};
  const inList = cardIds.map(encodeURIComponent).join(',');
  const rows = await sbFetch(
    `${REST}/gacha_collection?user_id=eq.${userId}&card_id=in.(${inList})&select=card_id,count`,
    { headers: headers() }
  );
  const map = {};
  for (const r of rows) map[r.card_id] = r.count;
  return map;
}

async function upsertCollection(rows) {
  // rows: [{user_id, card_id, count}]
  if (!rows.length) return;
  await sbFetch(`${REST}/gacha_collection`, {
    method: 'POST',
    headers: headers({ Prefer: 'resolution=merge-duplicates,return=minimal' }),
    body: JSON.stringify(rows),
  });
}

// ---- announcements (UR 이상 레어 드랍 공지) ----
async function insertAnnouncements(rows) {
  // rows: [{nickname, member, card_id, rarity}]
  if (!rows.length) return;
  await sbFetch(`${REST}/gacha_announcements`, {
    method: 'POST',
    headers: headers({ Prefer: 'return=minimal' }),
    body: JSON.stringify(rows),
  });
}

async function getRecentAnnouncements(limit) {
  const sinceIso = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  return sbFetch(
    `${REST}/gacha_announcements?created_at=gte.${encodeURIComponent(sinceIso)}` +
      `&nickname=not.eq.${encodeURIComponent('플로우검증봇')}` +
      `&order=created_at.desc&limit=${limit || 20}&select=nickname,member,rarity,card_id,created_at`,
    { headers: headers() }
  );
}

// 특정 카드들의 보유 수량을 지정 값으로 덮어쓴다 (분해용).
// rows: [{user_id, card_id, count}]  count 는 최종 절대 수량.
async function setCollectionCounts(rows) {
  if (!rows.length) return;
  await sbFetch(`${REST}/gacha_collection`, {
    method: 'POST',
    headers: headers({ Prefer: 'resolution=merge-duplicates,return=minimal' }),
    body: JSON.stringify(rows),
  });
}

// ---- 도감 완성 보상 (gacha_member_rewards, migration2 필요) ----
async function getMemberRewards(userId) {
  return sbFetch(
    `${REST}/gacha_member_rewards?user_id=eq.${userId}&select=member`,
    { headers: headers() }
  );
}

async function insertMemberReward(userId, member) {
  return sbFetch(`${REST}/gacha_member_rewards`, {
    method: 'POST',
    headers: headers({ Prefer: 'return=minimal' }),
    body: JSON.stringify({ user_id: userId, member }),
  });
}

module.exports = {
  getUserByKey,
  insertUser,
  updateUser,
  getCollection,
  getCollectionCounts,
  upsertCollection,
  setCollectionCounts,
  insertAnnouncements,
  getRecentAnnouncements,
  getMemberRewards,
  insertMemberReward,
  REST,
  headers,
  sbFetch,
};
