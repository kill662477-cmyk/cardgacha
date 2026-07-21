import crypto from 'node:crypto';

function sqlSeedRoll(seed, counter) {
  const hash = crypto.createHash('sha256').update(`${seed}:${counter}`).digest('hex');
  const hex = hash.substring(0, 8);
  return parseInt(hex, 16) / 4294967296;
}

function JSSeededRandom(seed) {
  let x = Math.sin(seed++) * 10000;
  return x - Math.floor(x);
}

const seed = Date.now();
const sqlVal = 1 + Math.floor(sqlSeedRoll(seed, 0) * 9);
const jsVal = 1 + Math.floor(JSSeededRandom(seed) * 9);

console.log("SQL:", sqlVal);
console.log("JS:", jsVal);

const sqlArr = [];
const jsArr = [];
for(let i=0; i<170; i++) {
  sqlArr.push(1 + Math.floor(sqlSeedRoll(seed, i) * 9));
  jsArr.push(1 + Math.floor(JSSeededRandom(seed + i) * 9));
}

console.log("Match?", JSON.stringify(sqlArr) === JSON.stringify(jsArr));
