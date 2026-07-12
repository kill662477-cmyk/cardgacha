// 임시 디버그: 프로덕션이 실제 읽는 redirect/client 값을 확인. 삭제 예정.
const { sendJson } = require('../../lib/http');

module.exports = async function handler(req, res) {
  const donationClientId = process.env.SOOP_DONATION_CLIENT_ID || process.env.SOOP_CLIENT_ID;
  return sendJson(res, 200, {
    donationClientId: donationClientId || '(미설정)',
    donationClientIdSource: process.env.SOOP_DONATION_CLIENT_ID ? 'SOOP_DONATION_CLIENT_ID' : '(폴백) SOOP_CLIENT_ID',
    mainClientId: process.env.SOOP_CLIENT_ID || '(미설정)',
    donationRedirectUri: process.env.SOOP_DONATION_REDIRECT_URI || '(미설정)',
    bridgeSecretSet: Boolean(process.env.SOOP_DONATION_BRIDGE_SECRET),
  });
};
