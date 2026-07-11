const fs = require('fs');
const path = require('path');

const frames = {
  C: ['#738095', '#2b3442', '#51cfff'],
  U: ['#557fab', '#253b5d', '#75e6ff'],
  R: ['#397ce5', '#182d67', '#65b5ff'],
  RR: ['#4c8ee8', '#172a60', '#b6e7ff'],
  RRR: ['#5276d7', '#1b225a', '#d8e5ff'],
  AR: ['#c7cbd8', '#574d7f', '#d88cff'],
  CHR: ['#d8e1e9', '#5a346c', '#83f5df'],
  HR: ['#d7a93d', '#4d3712', '#ffe699'],
  SR: ['#ffd35a', '#72500c', '#fff0a8'],
  SAR: ['#ff9d35', '#6f260e', '#ffdf87'],
  UR: ['#ff5db7', '#6b1c6f', '#ffa2ef'],
  MUR: ['#49dff5', '#1c2a4e', '#ff83e8'],
  FUR: ['#ff64d8', '#4a3879', '#8ff8ff'],
};

const outDir = path.join(__dirname, '..', 'assets', 'frames');
fs.mkdirSync(outDir, { recursive: true });

function svg(rarity, [main, shade, accent]) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1434" viewBox="0 0 1024 1434">
  <defs>
    <linearGradient id="metal" x1="0" x2="1" y1="0" y2="1"><stop stop-color="${main}"/><stop offset=".48" stop-color="${shade}"/><stop offset="1" stop-color="${main}"/></linearGradient>
    <linearGradient id="accent" x1="0" x2="1"><stop stop-color="${accent}" stop-opacity=".15"/><stop offset=".5" stop-color="${accent}"/><stop offset="1" stop-color="${accent}" stop-opacity=".15"/></linearGradient>
  </defs>
  <rect x="12" y="12" width="1000" height="1410" rx="34" fill="none" stroke="url(#metal)" stroke-width="7"/>
  <rect x="25" y="25" width="974" height="1384" rx="25" fill="none" stroke="${shade}" stroke-width="8"/>
  <rect x="31" y="31" width="962" height="1372" rx="20" fill="none" stroke="${accent}" stroke-width="3"/>
  <path d="M54 18H184L158 43H58ZM970 18H840L866 43H966ZM54 1416H184L158 1391H58ZM970 1416H840L866 1391H966Z" fill="url(#metal)"/>
  <path d="M18 54V184L43 158V58ZM1006 54V184L981 158V58ZM18 1380V1250L43 1276V1376ZM1006 1380V1250L981 1276V1376Z" fill="url(#metal)"/>
  <path d="M198 29H826M198 1405H826" fill="none" stroke="url(#accent)" stroke-width="3"/>
  <path d="M29 198V1236M995 198V1236" fill="none" stroke="url(#accent)" stroke-width="3"/>
</svg>`;
}

for (const [rarity, colors] of Object.entries(frames)) {
  fs.writeFileSync(path.join(outDir, `${rarity.toLowerCase()}.svg`), svg(rarity, colors));
}

console.log(`Generated ${Object.keys(frames).length} fixed 1024x1434 card frames.`);
