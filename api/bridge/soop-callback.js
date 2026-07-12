const { getQuery, sendJson } = require('../../lib/http');
const { enforceRateLimit } = require('../../lib/security');
const { sessionFrom, setSoopToken } = require('../../lib/bridge-auth');

const TOKEN_URL = 'https://openapi.sooplive.com/auth/token';
const STATION_URL = 'https://openapi.sooplive.com/user/stationinfo';

function redirect(res, location) {
  res.statusCode = 302;
  res.setHeader('Location', location);
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Cache-Control', 'no-store');
  res.end();
}

async function exchangeToken(clientId, clientSecret, redirectUri, code) {
  const body = new URLSearchParams({
    grant_type: 'authorization_code', client_id: clientId, client_secret: clientSecret, redirect_uri: redirectUri, code,
  });
  const response = await fetch(TOKEN_URL, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: body.toString(),
  });
  if (!response.ok) throw new Error(`token exchange failed: ${response.status}`);
  const data = await response.json();
  if (!data?.access_token) throw new Error('token exchange: no access_token');
  return data.access_token;
}

async function fetchStationId(accessToken) {
  const body = new URLSearchParams({ access_token: accessToken });
  const response = await fetch(STATION_URL, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: body.toString(),
  });
  if (!response.ok) throw new Error(`stationinfo failed: ${response.status}`);
  const data = await response.json();
  const soopId = (data?.data?.station_name || '').toString().trim();
  if (data?.result !== 1 || !soopId) throw new Error('stationinfo: no station_name');
  return soopId;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method not allowed' });
  const session = sessionFrom(req);
  if (!session?.soopId) return redirect(res, '/donation-bridge.html?error=auth');
  if (!await enforceRateLimit(req, res, 'soop-bridge-callback', 12, 300)) return;

  const clientId = process.env.SOOP_DONATION_CLIENT_ID || process.env.SOOP_CLIENT_ID;
  const clientSecret = process.env.SOOP_DONATION_CLIENT_SECRET || process.env.SOOP_CLIENT_SECRET;
  const redirectUri = process.env.SOOP_DONATION_REDIRECT_URI;
  const code = (getQuery(req).code || '').toString().trim();
  if (!clientId || !clientSecret || !redirectUri || !code) return redirect(res, '/donation-bridge.html?error=soop');

  try {
    const accessToken = await exchangeToken(clientId, clientSecret, redirectUri, code);
    const soopId = await fetchStationId(accessToken);
    if (soopId !== session.soopId) return redirect(res, '/donation-bridge.html?error=mismatch');
    setSoopToken(res, accessToken, soopId);
    return redirect(res, '/donation-bridge.html?connected=1');
  } catch (error) {
    console.error('soop bridge callback error', error?.message || error);
    return redirect(res, '/donation-bridge.html?error=soop');
  }
};
