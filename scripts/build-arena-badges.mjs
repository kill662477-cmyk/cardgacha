// 투기장 티어 뱃지 SVG 를 생성한다.
// 손으로 10장을 그려 두면 색을 바꿀 때마다 전부 다시 손봐야 하므로,
// ARENA_RULES 의 티어 색을 읽어 파일로 굽는다. 색을 바꾸면 이 스크립트만 다시 돌리면 된다.
//
//   node scripts/build-arena-badges.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { ARENA_RULES } from '../src/renewal/config.js';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const outDir = path.join(root, 'assets', 'renewal', 'arena');
mkdirSync(outDir, { recursive: true });

// 티어마다 실루엣이 달라야 작게 봐도 구분된다. 색만 바꾸면 축소했을 때 전부 같아 보인다.
const ORNAMENTS = {
  // 아이언: 장식 없는 맨 방패. 출발선이라는 인상.
  iron: () => '<path d="M32 22 L32 42" stroke="var(--edge)" stroke-width="3" stroke-linecap="round" opacity=".55"/>',
  // 브론즈: 갈매기 하나.
  bronze: () => '<path d="M22 30 L32 24 L42 30" fill="none" stroke="var(--edge)" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/>',
  // 실버: 갈매기 둘.
  silver: () => `
    <path d="M22 28 L32 22 L42 28" fill="none" stroke="var(--edge)" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M22 37 L32 31 L42 37" fill="none" stroke="var(--edge)" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" opacity=".75"/>`,
  // 골드: 월계관.
  gold: () => `
    <path d="M22 36 C20 28 24 21 32 18 C40 21 44 28 42 36" fill="none" stroke="var(--edge)" stroke-width="2.6" stroke-linecap="round"/>
    <circle cx="32" cy="31" r="5.4" fill="var(--edge)"/>`,
  // 플래티넘: 각진 보석.
  platinum: () => `
    <path d="M32 18 L42 27 L32 44 L22 27 Z" fill="var(--edge)" opacity=".92"/>
    <path d="M22 27 L42 27" stroke="var(--core)" stroke-width="1.6" opacity=".6"/>`,
  // 에메랄드: 사각 컷 보석.
  emerald: () => `
    <path d="M25 22 H39 L43 28 L32 43 L21 28 Z" fill="var(--edge)" opacity=".92"/>
    <path d="M21 28 H43 M25 22 L32 43 M39 22 L32 43" stroke="var(--core)" stroke-width="1.4" opacity=".55" fill="none"/>`,
  // 다이아: 마름모 + 광채.
  diamond: () => `
    <path d="M32 17 L44 30 L32 45 L20 30 Z" fill="var(--edge)" opacity=".92"/>
    <path d="M26 30 L32 22 L38 30 L32 38 Z" fill="var(--core)" opacity=".55"/>`,
  // 마스터: 별.
  master: () => '<path d="M32 16 L36 27 L48 27 L38 34 L42 45 L32 38 L22 45 L26 34 L16 27 L28 27 Z" fill="var(--edge)"/>',
  // 그랜드마스터: 별 + 날개.
  grandmaster: () => `
    <path d="M32 17 L35.4 26.6 L45.6 26.6 L37.4 32.6 L40.6 42.2 L32 36.2 L23.4 42.2 L26.6 32.6 L18.4 26.6 L28.6 26.6 Z" fill="var(--edge)"/>
    <path d="M14 30 L21 33 L14 36 Z M50 30 L43 33 L50 36 Z" fill="var(--edge)" opacity=".8"/>`,
  // 챌린저: 왕관. 점수가 아니라 등수로 정해지는 자리라 혼자 형태가 다르다.
  challenger: () => `
    <path d="M18 40 L15 22 L23 29 L32 17 L41 29 L49 22 L46 40 Z" fill="var(--edge)"/>
    <rect x="18" y="41" width="28" height="4.4" rx="2.2" fill="var(--edge)" opacity=".85"/>`,
};

function badgeSvg(tier) {
  const ornament = (ORNAMENTS[tier.key] ?? ORNAMENTS.iron)().trim();
  // 방패 안쪽을 어둡게 깔아야 밝은 티어 색에서도 장식이 보인다.
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64" role="img" aria-label="${tier.label}">
  <title>${tier.label}</title>
  <defs>
    <linearGradient id="plate-${tier.key}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${tier.color}"/>
      <stop offset="1" stop-color="${tier.accent}"/>
    </linearGradient>
  </defs>
  <g style="--core:${tier.color};--edge:${tier.accent}">
    <path d="M32 3 L57 11 V31 C57 45 46 55 32 61 C18 55 7 45 7 31 V11 Z"
          fill="url(#plate-${tier.key})" stroke="${tier.color}" stroke-width="2.2" stroke-linejoin="round"/>
    <path d="M32 9 L51 15 V31 C51 41.5 42.5 49.5 32 54.5 C21.5 49.5 13 41.5 13 31 V15 Z"
          fill="#080d0a" opacity=".62"/>
    ${ornament}
  </g>
</svg>
`;
}

const tiers = [...ARENA_RULES.tiers, ARENA_RULES.challengerTier];
for (const tier of tiers) {
  writeFileSync(path.join(outDir, `${tier.key}.svg`), badgeSvg(tier), 'utf8');
}
console.log(`arena badges written: ${tiers.length} files -> assets/renewal/arena/`);
