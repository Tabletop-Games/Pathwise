import { randomInt } from 'node:crypto';
import { readFileSync } from 'node:fs';

export const fortunePrizes = JSON.parse(readFileSync(new URL('./fortune-prizes.json', import.meta.url)));
export const wheelWindow = 24 * 60 * 60 * 1000;
export const liveWheelStamps = (state, now) => (state?.stamps ?? []).filter(
  stamp => stamp > now - wheelWindow,
);

export function pickFortune(roll) {
  if (!Number.isInteger(roll) || roll < 0 || roll >= 100) throw new RangeError('Invalid wheel roll');
  let end = 0;
  for (const prize of fortunePrizes) {
    end += prize.weight;
    if (roll < end) return prize.id;
  }
  throw new Error('Invalid wheel catalog');
}

// Called from the same Firestore transaction as the signed receipt claim.
export function awardFortune(state, now, receipt, roll = randomInt(100)) {
  const stamps = liveWheelStamps(state, now);
  if (stamps.length >= 4) return null;
  const prize = pickFortune(roll);
  const counts = { ...state?.counts };
  counts[prize] = (counts[prize] ?? 0) + 1;
  return { stamps: [...stamps, now], counts, last: prize, receipt };
}

export function publicFortune(state, now) {
  return {
    version: 2, now, stamps: liveWheelStamps(state, now), counts: state?.counts ?? {},
    last: state?.last ?? null, receipt: state?.receipt ?? null,
  };
}
