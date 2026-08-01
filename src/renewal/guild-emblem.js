import { escapeHtml } from './html.js';

// 기본 엠블럼 8종은 이모지 기호로 그린다.
export const EMBLEM_GLYPHS = Object.freeze({
  shield: '🛡', bolt: '⚡', star: '★', crown: '♛',
  flame: '🔥', blade: '⚔', hexcore: '⬢', signal: '📡',
});

// 이미지 에셋이 있는 커스텀 엠블럼(PDB-16 7.2). 키가 여기 있으면 이모지 대신 이미지를 쓴다.
// 새 엠블럼을 추가할 때는 assets/renewal/guild/emblems/<key>.png(256x256) 배치 +
// gacha_s2_guild_emblems 행 삽입 + 여기 한 줄이면 된다.
// 파일명을 그대로 두고 이미지를 교체하면(크롭 조정 등) 브라우저가 옛 파일을 계속 쓴다.
// 그래서 경로에 버전을 붙인다. 이미지를 새로 만들 때마다 이 값을 올릴 것.
const EMBLEM_ASSET_VERSION = '202608011957';

export const EMBLEM_IMAGES = Object.freeze({
  ilsin: `assets/renewal/guild/emblems/ilsin.png?v=${EMBLEM_ASSET_VERSION}`,
  chiri: `assets/renewal/guild/emblems/chiri.png?v=${EMBLEM_ASSET_VERSION}`,
  byungdan: `assets/renewal/guild/emblems/byungdan.png?v=${EMBLEM_ASSET_VERSION}`,
  harang: `assets/renewal/guild/emblems/harang.png?v=${EMBLEM_ASSET_VERSION}`,
  calmsnal: `assets/renewal/guild/emblems/calmsnal.png?v=${EMBLEM_ASSET_VERSION}`,
  jjiking: `assets/renewal/guild/emblems/jjiking.png?v=${EMBLEM_ASSET_VERSION}`,
  sexyterran: `assets/renewal/guild/emblems/sexyterran.png?v=${EMBLEM_ASSET_VERSION}`,
  s2jjaek: `assets/renewal/guild/emblems/s2jjaek.png?v=${EMBLEM_ASSET_VERSION}`,
});

// textContent 로 넣는 자리에서 쓰는 문자 표현. 이미지 엠블럼도 텍스트 문맥에서는 기호로 대체된다.
export function emblemGlyph(key) {
  return EMBLEM_GLYPHS[key] ?? EMBLEM_GLYPHS.shield;
}

// innerHTML 로 넣는 자리에서 쓰는 마크업. 이미지가 있으면 img, 없으면 이모지.
// key 는 서버에서 온 값이라 그대로 신뢰하지 않고 화이트리스트에 있을 때만 이미지 경로를 만든다.
export function emblemMarkup(key, className = 'guild-emblem-glyph') {
  const image = EMBLEM_IMAGES[key];
  if (image) {
    return `<img class="${className} guild-emblem-image" src="${image}" alt="" loading="lazy">`;
  }
  return `<span class="${className}">${escapeHtml(emblemGlyph(key))}</span>`;
}
