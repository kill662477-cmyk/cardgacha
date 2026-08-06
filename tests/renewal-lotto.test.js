import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  LOTTO_RULES,
  lottoRankForMatches,
  normalizeLottoNumbers,
  pickRandomLottoNumbers,
} from '../src/renewal/lotto.js';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const sql = await read('supabase/migrations/20260727093000_lotto_minigame.sql');
const historySql = await read('supabase/migrations/20260727113000_lotto_weekly_history.sql');
const expansionSql = await read('supabase/migrations/20260802123000_lotto_two_tickets_first_pool_1m.sql');
const normalizedSql = sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const normalizedHistorySql = historySql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const normalizedExpansionSql = expansionSql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').toLowerCase();
const html = await read('index.html');
const controller = await read('src/renewal/minigame-controller.js');
const runtime = await read('src/renewal/remote-runtime.js');

assert.deepEqual(LOTTO_RULES.drawHoursKst, [10, 15, 20]);
assert.equal(LOTTO_RULES.minimumNumber, 1);
assert.equal(LOTTO_RULES.maximumNumber, 16);
assert.equal(LOTTO_RULES.picks, 6);
assert.equal(LOTTO_RULES.ticketCost, 1_000);
assert.equal(LOTTO_RULES.ticketLimit, 2);
assert.equal(LOTTO_RULES.firstPoolCap, 1_000_000);
assert.equal(LOTTO_RULES.salesCloseMinutes, 10);
assert.equal(LOTTO_RULES.thirdPrize, 2_000);
assert.equal(LOTTO_RULES.fourthPrize, 1_000);
assert.deepEqual(normalizeLottoNumbers([16, 4, 1, 13, 10, 7]), [1, 4, 7, 10, 13, 16]);
assert.deepEqual(normalizeLottoNumbers([1, 1, 7, 10, 13, 16]), []);
// 2026-08-05: 상한을 16 으로 내렸다. 범위를 벗어난 번호는 걸러져야 한다.
assert.deepEqual(normalizeLottoNumbers([17, 4, 1, 13, 10, 7]), []);
assert.deepEqual(pickRandomLottoNumbers(() => 0), [2, 3, 4, 5, 6, 7]);
assert.deepEqual([6, 5, 4, 3, 2].map(lottoRankForMatches), [1, 2, 3, 4, null]);

for (const table of ['gacha_s2_lotto_rounds', 'gacha_s2_lotto_tickets', 'gacha_s2_lotto_payouts']) {
  assert.match(normalizedSql, new RegExp(`create table if not exists public\\.${table}`));
  assert.match(normalizedSql, new RegExp(`alter table public\\.${table} enable row level security`));
  assert.match(normalizedSql, new RegExp(`revoke all on table public\\.${table} from public, anon, authenticated`));
}
assert.match(normalizedExpansionSql, /drop constraint if exists gacha_s2_lotto_tickets_round_id_user_id_key/);
assert.match(normalizedExpansionSql, /v_ticket_count >= 2/);
assert.match(normalizedExpansionSql, /'ticketlimit', 2/);
assert.match(normalizedExpansionSql, /least\(1000000::bigint/);
assert.match(normalizedExpansionSql, /on conflict \(ticket_id\) do nothing/);
assert.match(normalizedExpansionSql, /sum\(inserted\.points\)/);
assert.match(normalizedSql, /cardinality\(p_numbers\) = 6/);
assert.match(normalizedSql, /min\(value\) >= 1 and max\(value\) <= 18/);
assert.match(normalizedSql, /p_draw_at - interval '10 minutes'/);
assert.match(normalizedSql, /100000 \+ coalesce\(v_first_carry, 0\)/);
assert.match(normalizedSql, /50000 \+ coalesce\(v_second_carry, 0\)/);
assert.match(normalizedSql, /least\(500000::bigint/);
assert.match(normalizedSql, /when 3 then 2000/);
assert.match(normalizedSql, /when 4 then 1000/);
assert.match(normalizedSql, /set points = state\.points \+ inserted\.points,\s*revision = state\.revision \+ 1/);
assert.match(normalizedSql, /on conflict \(round_id, user_id\) do nothing/);
assert.match(normalizedSql, /pg_advisory_xact_lock\(hashtext\('gacha_s2_lotto_settlement'\)\)/);
assert.match(normalizedSql, /'0 1,6,11 \* \* \*'/, '10·15·20시 KST 추첨 cron이 필요하다');
assert.match(normalizedSql, /'lotto_first', 'lotto_second'/);
assert.match(normalizedSql, /payout\.rank in \(1, 2\)/);
assert.doesNotMatch(normalizedSql, /gacha_s2_minigame_daily/, '로또는 기존 미니게임 일일 보상 한도와 분리해야 한다');

assert.match(html, /data-minigame-select="lotto"/);
assert.match(html, /id="lottoNumberGrid"/);
assert.match(html, /id="lottoAutoPickButton"/);
assert.match(html, /최근 1·2등 당첨자/);
assert.match(html, /id="lottoHistoryButton"[^>]*>역대 당첨번호</);
assert.match(html, /id="lottoHistoryDialog"/);
assert.match(controller, /GAME_COMMAND_TYPES|buyLottoTicket|loadLottoState/);
// 자동 선택도 그 회차의 상한을 따라야 한다. 범위 밖 번호를 내면 구매가 서버에서 거부된다.
assert.match(controller, /pickRandomLottoNumbers\(random, currentLottoMaxNumber\(\)\)/);
// 번호판·입력 검사도 회차 값을 써야 진행 중 회차(1~18)가 16칸으로 줄지 않는다.
assert.match(controller, /function currentLottoMaxNumber\(\)/);
assert.match(controller, /Array\.from\(\{ length: maxNumber \}/, '번호판은 회차 상한으로 그려야 한다');
assert.match(controller, /getState\(\)\.points < LOTTO_RULES\.ticketCost/);
assert.match(controller, /miniGameMode\.hidden = lotto \|\| ladder/);
assert.match(controller, /Array\.isArray\(lottoState\?\.history\)/);
assert.doesNotMatch(controller, /getLottoHistory/, '버튼 클릭은 별도 서버 조회를 만들면 안 된다');
assert.match(runtime, /event_rank,points,lotto_round_id/);
assert.match(normalizedHistorySql, /create or replace function public\.gacha_s2_get_lotto_state_v2/);
assert.match(normalizedHistorySql, /::date - 6/);
assert.match(normalizedHistorySql, /limit 21/);
assert.match(normalizedHistorySql, /public\.gacha_s2_get_lotto_state\(p_user_id\).*public\.gacha_s2_get_lotto_history\(p_user_id\)/);

console.log('renewal lotto tests passed: 6/18 ticket, capped rollover, isolated economy, atomic auto payout, winner ticker');
