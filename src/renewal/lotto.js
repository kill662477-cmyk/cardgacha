export const LOTTO_RULES = Object.freeze({
  minimumNumber: 1,
  maximumNumber: 18,
  picks: 6,
  ticketCost: 1_000,
  ticketLimit: 2,
  firstPoolCap: 1_000_000,
  salesCloseMinutes: 10,
  drawHoursKst: Object.freeze([10, 15, 20]),
  thirdPrize: 2_000,
  fourthPrize: 1_000,
});

export function pickRandomLottoNumbers(random) {
  if (typeof random !== 'function') throw new TypeError('lotto random adapter is required');
  const pool = Array.from(
    { length: LOTTO_RULES.maximumNumber - LOTTO_RULES.minimumNumber + 1 },
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
