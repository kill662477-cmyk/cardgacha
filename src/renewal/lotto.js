export const LOTTO_RULES = Object.freeze({
  minimumNumber: 1,
  // 2026-08-05: 1~18 -> 1~16. 서버는 회차마다 max_number 를 기록해 두므로
  // 이 값이 바뀌어도 이미 팔린 회차는 팔릴 때의 범위로 추첨된다.
  maximumNumber: 16,
  picks: 6,
  ticketCost: 1_000,
  ticketLimit: 2,
  firstPoolCap: 1_000_000,
  salesCloseMinutes: 10,
  drawHoursKst: Object.freeze([10, 15, 20]),
  thirdPrize: 2_000,
  fourthPrize: 1_000,
});

// maxNumber 를 넘기면 그 회차의 범위에서 뽑는다. 회차마다 상한이 다를 수 있어
// (1~18 로 팔린 회차가 남아 있다) 자동 선택이 범위 밖 번호를 내면 구매가 거부된다.
export function pickRandomLottoNumbers(random, maxNumber = LOTTO_RULES.maximumNumber) {
  if (typeof random !== 'function') throw new TypeError('lotto random adapter is required');
  const maximum = Number.isInteger(maxNumber) && maxNumber >= LOTTO_RULES.picks
    ? maxNumber
    : LOTTO_RULES.maximumNumber;
  const pool = Array.from(
    { length: maximum - LOTTO_RULES.minimumNumber + 1 },
    (_, index) => index + LOTTO_RULES.minimumNumber,
  );
  for (let index = pool.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(random() * (index + 1));
    [pool[index], pool[swapIndex]] = [pool[swapIndex], pool[index]];
  }
  return pool.slice(0, LOTTO_RULES.picks).sort((left, right) => left - right);
}

export function normalizeLottoNumbers(values) {
  if (!Array.isArray(values)) return [];
  const numbers = values.map(Number);
  if (
    numbers.length !== LOTTO_RULES.picks
    || numbers.some((value) => !Number.isInteger(value)
      || value < LOTTO_RULES.minimumNumber
      || value > LOTTO_RULES.maximumNumber)
    || new Set(numbers).size !== numbers.length
  ) return [];
  return numbers.sort((left, right) => left - right);
}

export function lottoRankForMatches(matches) {
  if (matches === 6) return 1;
  if (matches === 5) return 2;
  if (matches === 4) return 3;
  if (matches === 3) return 4;
  return null;
}

export function lottoBallMarkup(numbers, { hits = [], className = '' } = {}) {
  const hitSet = new Set(hits);
  return numbers.map((value) => (
    `<i class="lotto-ball${hitSet.has(value) ? ' hit' : ''}${className ? ` ${className}` : ''}">${value}</i>`
  )).join('');
}
