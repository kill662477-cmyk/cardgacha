// 임시 디버그: 프로덕션이 실제 읽는 redirect_uri 값을 확인. 삭제 예정.
const { sendJson } = require('../../lib/http');

module.exports = async function handler(req, res) {
  return sendJson(res, 200, {
    donationRedirectUri: process.env.SOOP_DONATION_REDIRECT_URI || '(미설정)',
    donationRedirectLength: (process.env.SOOP_DONATION_REDIRECT_URI || '').length,
    mainRedirectUri: process.env.SOOP_REDIRECT_URI || '(미설정)',
    clientIdSet: Boolean(process.env.SOOP_CLIENT_ID),
    bridgeSecretSet: Boolean(process.env.SOOP_DONATION_BRIDGE_SECRET),
  });
};
