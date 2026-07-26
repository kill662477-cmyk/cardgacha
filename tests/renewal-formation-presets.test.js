import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { GAME_COMMAND_TYPES, createGameCommand, validateGameCommand } from '../src/renewal/service-contract.js';

const sql = await readFile(new URL('../supabase/migrations/20260726000114_formation_presets.sql', import.meta.url), 'utf8');
const contract = await readFile(new URL('../src/renewal/service-contract.js', import.meta.url), 'utf8');
const router = await readFile(new URL('../src/renewal/server-command-router.js', import.meta.url), 'utf8');
const app = await readFile(new URL('../src/renewal/app.js', import.meta.url), 'utf8');
const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');

const formation = ['a-1', 'a-2', 'a-3', 'a-4', 'a-5'];
const build = (type, payload) => createGameCommand({
  type, payload, expectedRevision: 3, idempotencyKey: 'preset-cmd-0001', clientSentAt: 1,
});

// 명령 계약: 세 명령 모두 payload 를 통과해야 한다.
// (길드 작업에서 allowedFields 를 빠뜨려 라이브에서 전부 거절된 적이 있다.)
for (const [type, payload] of [
  [GAME_COMMAND_TYPES.SAVE_FORMATION_PRESET, { presetId: '월드보스', formation }],
  [GAME_COMMAND_TYPES.APPLY_FORMATION_PRESET, { presetId: '월드보스' }],
  [GAME_COMMAND_TYPES.DELETE_FORMATION_PRESET, { presetId: '월드보스' }],
]) {
  assert.equal(validateGameCommand(build(type, payload)).valid, true, `${type} 가 계약을 통과해야 한다`);
}

// createGameCommand 는 잘못된 명령을 만들지 않고 그 자리에서 던진다.
const rejects = (payload, why) => assert.throws(
  () => build(GAME_COMMAND_TYPES.SAVE_FORMATION_PRESET, payload),
  /Invalid game command/,
  why,
);
rejects({ presetId: '가나다라마바사아자차카타파', formation }, '이름 12자 초과');
rejects({ presetId: 'ok', formation: formation.slice(0, 4) }, '카드 5장 아님');
rejects({ presetId: 'ok', formation: ['a-1', 'a-1', 'a-2', 'a-3', 'a-4'] }, '중복 카드');
assert.throws(
  () => build(GAME_COMMAND_TYPES.APPLY_FORMATION_PRESET, { presetId: 'ok', formation }),
  /Invalid game command/,
  'apply 에는 formation 필드가 없다',
);

// 라우터가 세 명령을 RPC 로 연결해야 한다.
for (const rpc of ['gacha_s2_save_formation_preset', 'gacha_s2_apply_formation_preset', 'gacha_s2_delete_formation_preset']) {
  assert.match(router, new RegExp(rpc), `${rpc} 매핑 누락`);
  assert.match(sql, new RegExp(`create or replace function public\.${rpc}`), `${rpc} 정의 누락`);
}
assert.match(router, /p_preset_id: payload\.presetId/);

// 5개 상한과 편성 가능 조건은 서버에서 강제돼야 한다.
assert.match(sql, /최대 5개까지 저장할 수 있습니다/);
assert.match(sql, />= 5 then/, '프리셋 개수 상한 검사 누락');
assert.match(sql, /catalog\.rarity <> 'EX'/);
assert.match(sql, /gacha_s2_collection_records/);
// 적용 시점에도 다시 검사해야 한다. 저장 후 카드를 잃을 수 있다.
assert.match(sql, /지금 편성할 수 없는 카드가 있습니다/);
// 활성 프리셋을 지우면 active_formation_preset_id 를 비워야 스냅샷 검증을 통과한다.
assert.match(sql, /case when v_active = v_name then null else v_active end/);

// UI 연결: 버튼이 화면에 있고 elements 에 등록되고 클릭이 붙어야 한다.
for (const id of ['formationPresetList', 'formationPresetName', 'formationPresetSave']) {
  assert.match(html, new RegExp(`id="${id}"`), `${id} 가 화면에 없다`);
  assert.match(app, new RegExp(`'${id}'`), `${id} 가 elements 목록에 없다`);
}
assert.match(app, /elements\.formationPresetSave\.addEventListener/);
assert.match(app, /elements\.formationPresetList\.addEventListener/);
// 프리셋 이름은 사용자 입력이라 화면에 이스케이프해서 그려야 한다.
assert.ok(app.includes('data-preset-apply="${escapeHtml(name)}"'));
assert.ok(app.includes('data-preset-delete="${escapeHtml(name)}"'));
// escapeHtml 을 쓰면서 import 를 빠뜨리면 프리셋이 하나라도 있는 순간
// renderFormationDialog 가 ReferenceError 로 죽어 편성 창이 아예 열리지 않는다.
// 실제로 그렇게 라이브에서 편성 버튼이 먹통이 됐다.
assert.match(
  app,
  /import \{ escapeHtml \} from '\.\/html\.js';/,
  'escapeHtml 을 쓰는 파일은 반드시 import 해야 한다',
);

console.log('formation preset tests passed: contract, router, server guards, wired UI');

// 레이아웃 회귀 가드.
// .dialog-shell 의 기본 행 정의는 3행이다. 편성 창은 프리셋 바 때문에 자식이 4개라
// 행 수를 맞춰 주지 않으면 선택 카드 줄이 남는 공간을 먹고 인벤토리가 아래 카드를 덮는다.
const css = await readFile(new URL('../styles/renewal/main.css', import.meta.url), 'utf8');
const dialogBody = html.slice(
  html.indexOf('<dialog class="formation-dialog"'),
  html.indexOf('</dialog>', html.indexOf('<dialog class="formation-dialog"')),
);
const shellChildren = (dialogBody.match(/^\s{6}<(?:div|header|section)\b/gm) ?? []).length;
const rowRule = css.match(/\.formation-dialog \.dialog-shell \{ grid-template-rows: ([^;]+); \}/);
assert.ok(rowRule, '편성 창 전용 grid-template-rows 규칙이 있어야 한다');
const rowCount = rowRule[1].trim().split(/\s+(?![^(]*\))/).length;
assert.equal(
  rowCount,
  shellChildren,
  `편성 창 자식 ${shellChildren}개에 맞춰 행을 ${shellChildren}개 정의해야 한다 (현재 ${rowCount}개)`,
);
assert.match(rowRule[1], /minmax\(0, 1fr\)$/, '마지막 행만 스크롤 영역이어야 한다');

console.log(`formation dialog layout guard passed: ${shellChildren} rows`);
