// Initial crew account and bridge-key issuance. Run once after migrations 9, 10, and 11.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const members = require('../data/soop-bridge-members.json');
const { REST, headers, sbFetch } = require('../lib/supabase');
const { newKey } = require('../lib/gacha');

const ROOT = path.resolve(__dirname, '..');
const OUT_DIR = path.join(ROOT, '.bridge-keys');

function hash(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function bridgeKey() {
  return `CMZB_${crypto.randomBytes(18).toString('base64url')}`;
}

async function findUser(soopId) {
  const rows = await sbFetch(`${REST}/gacha_users?soop_id=eq.${encodeURIComponent(soopId)}&select=id`, { headers: headers() });
  return rows?.[0] || null;
}

async function findBridgeKey(soopId) {
  const rows = await sbFetch(`${REST}/gacha_soop_bridge_keys?soop_id=eq.${encodeURIComponent(soopId)}&select=soop_id`, { headers: headers() });
  return rows?.[0] || null;
}

async function createUser(member) {
  await sbFetch(`${REST}/gacha_users`, {
    method: 'POST',
    headers: headers({ Prefer: 'return=minimal' }),
    body: JSON.stringify({
      soop_id: member.soopId,
      nickname: member.name,
      login_key_hash: hash(newKey()),
      points: 5000,
    }),
  });
}

async function createBridgeKey(member, rawKey) {
  await sbFetch(`${REST}/gacha_soop_bridge_keys`, {
    method: 'POST',
    headers: headers({ Prefer: 'return=minimal' }),
    body: JSON.stringify({ soop_id: member.soopId, key_hash: hash(rawKey), active: true }),
  });
}

async function run() {
  if (!process.argv.includes('--confirm')) {
    throw new Error('Run with --confirm. This creates crew game accounts and bridge keys.');
  }

  const issued = [];
  for (const member of members) {
    if (!await findUser(member.soopId)) await createUser(member);
    if (await findBridgeKey(member.soopId)) continue;
    const rawKey = bridgeKey();
    await createBridgeKey(member, rawKey);
    issued.push({ stationName: member.name, soopId: member.soopId, bridgeKey: rawKey });
  }

  if (!issued.length) {
    console.log('No bridge keys issued. Existing keys were kept.');
    return;
  }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const filename = `issued-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  const output = path.join(OUT_DIR, filename);
  fs.writeFileSync(output, JSON.stringify(issued, null, 2), { encoding: 'utf8', mode: 0o600 });
  console.log(`Issued ${issued.length} bridge keys: ${output}`);
}

run().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
