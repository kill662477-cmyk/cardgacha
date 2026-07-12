const members = require('../data/soop-bridge-members.json');

const bridgeSoopIds = new Set(members.map((member) => member.soopId));

function isBridgeMember(soopId) {
  return Boolean(soopId && bridgeSoopIds.has(soopId));
}

module.exports = { isBridgeMember };
