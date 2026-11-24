// Port of PuzzleId in lib/model/game_state.dart: maps a public puzzle key to a generation request.
import { generatePuzzle, puzzleSeed } from './generator.mjs';

export const levelCount = 1000;
export const dailyCheckpointCount = 3;

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const RUN = /^v2-[A-Za-z0-9-]{8,64}$/;

/** Returns {mode, key, size, level?, request} or null for an unrecognised key. */
export function parsePuzzleKey(key) {
  if (typeof key !== 'string' || key.length > 128) return null;
  let match = /^levels\/(\d{1,4})$/.exec(key);
  if (match) {
    const level = Number(match[1]);
    if (level < 1 || level > levelCount) return null;
    const size = level <= 30 ? 4 : level <= 100 ? 5 : level <= 300 ? 6 : 7;
    const baseline = [0, 0, 0, 0, 8, 11, 15, 18][size];
    const reduction = Math.min(Math.max(Math.trunc(level / 200), 0), 4);
    return { mode: 'levels', key, level, size,
      request: { size, seed: puzzleSeed(`pathwise-catalogue-v3/${key}`), clues: baseline - reduction } };
  }
  match = /^daily\/(\d{4}-\d{2}-\d{2})$/.exec(key);
  if (match && validDay(match[1])) return daily(key, match[1], null);
  match = /^daily-checkpoint\/(\d{4}-\d{2}-\d{2})\/([1-2])$/.exec(key);
  if (match && validDay(match[1])) return daily(key, match[1], Number(match[2]));
  match = /^attack\/(v2-[A-Za-z0-9-]{8,64})\/(\d{1,3})$/.exec(key);
  if (match && RUN.test(match[1])) {
    const index = Number(match[2]);
    const size = Math.min(Math.max(4 + Math.trunc(index / 3), 4), 7);
    const label = index < 3 ? null : ['Guided', 'Sparse', 'Standard'][index % 3 === 0 ? 0 : index % 3 === 1 ? 1 : 2];
    const baseline = [0, 0, 0, 0, 8, 10, 14, 16][size];
    const variation = label === 'Guided' ? 2 : label === 'Sparse' ? -2 : 0;
    return { mode: 'attack', key, run: match[1], index, size,
      request: { size, seed: puzzleSeed(`pathwise-attack-v2/${key}`), clues: baseline + variation } };
  }
  return null;
}

function validDay(day) {
  if (!DAY.test(day)) return false;
  const date = new Date(`${day}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().startsWith(day);
}

function daily(key, day, checkpoint) {
  const size = checkpoint === null ? 6 : 3 + checkpoint;
  const targets = [0, 0, 0, 0, 7, 10, 14, 18];
  return { mode: 'daily', key, day, checkpoint, size,
    request: { size, seed: puzzleSeed(`pathwise-v1/${key}`), clues: targets[size] } };
}

const cache = new Map();
let catalogue = null;
export function useCatalogue(levels) { catalogue = levels; }

export function buildPuzzle(parsed) {
  if (parsed.mode === 'levels' && catalogue?.[parsed.level]) return catalogue[parsed.level];
  const cached = cache.get(parsed.key);
  if (cached) return cached;
  const board = generatePuzzle(parsed.request, { level: parsed.mode === 'levels' ? parsed.level : 0 });
  if (cache.size > 256) cache.delete(cache.keys().next().value);
  cache.set(parsed.key, board);
  return board;
}
