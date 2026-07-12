const fs = require('fs');
const path = require('path');

// Archive-print frames: thin marks that protect the art instead of covering it.
const frames = {
  C: ['#68716c', '#e9eee8'],
  U: ['#39966a', '#e1f3e8'],
  R: ['#287ca9', '#e1eff5'],
  RR: ['#466dc8', '#e5e9f8'],
  RRR: ['#7258b6', '#eee9f8'],
  AR: ['#b34a96', '#f8e7f1'],
  CHR: ['#058c89', '#ddf5f0'],
  HR: ['#cf593c', '#fae8df'],
  SR: ['#bd8615', '#fbf2d9'],
  SAR: ['#dc6c1c', '#feead9'],
  UR: ['#be3c64', '#f8e2e9'],
  MUR: ['#147a9c', '#dff3f7'],
  FUR: ['#8a397f', '#f6e2f1'],
};

const outDir = path.join(__dirname, '..', 'assets', 'frames');
fs.mkdirSync(outDir, { recursive: true });

function svg(rarity, [ink, paper]) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1434" viewBox="0 0 1024 1434">
  <path d="M24 78V24H78 M946 24H1000V78 M1000 1356V1410H946 M78 1410H24V1356" fill="none" stroke="${ink}" stroke-width="5"/>
  <path d="M39 180V39H180 M844 39H985V180 M985 1254V1395H844 M180 1395H39V1254" fill="none" stroke="${paper}" stroke-width="3" opacity=".9"/>
  <path d="M39 232V80 M985 232V80 M39 1202V1354 M985 1202V1354" fill="none" stroke="${ink}" stroke-width="2" opacity=".72"/>
  <path d="M73 55H332 M692 55H951 M73 1379H332 M692 1379H951" fill="none" stroke="${ink}" stroke-width="2" opacity=".78"/>
  <rect x="54" y="54" width="112" height="31" fill="${ink}"/>
  <text x="110" y="75" text-anchor="middle" fill="#ffffff" font-family="monospace" font-size="18" font-weight="700">${rarity}</text>
  <text x="512" y="80" text-anchor="middle" fill="${ink}" font-family="monospace" font-size="14" font-weight="700" opacity=".88">CMZ ARCHIVE</text>
  <text x="512" y="1372" text-anchor="middle" fill="${ink}" font-family="monospace" font-size="13" font-weight="700" opacity=".82">COLLECTOR EDITION</text>
</svg>`;
}

for (const [rarity, colors] of Object.entries(frames)) {
  fs.writeFileSync(path.join(outDir, `${rarity.toLowerCase()}.svg`), svg(rarity, colors));
}

console.log(`Generated ${Object.keys(frames).length} archive-print card frames.`);
