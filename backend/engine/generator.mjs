// Port of lib/logic/puzzle_generator.dart (non-legacy boards only).
import { Puzzle } from './puzzle.mjs';
import { difficultyScore, mechanicInfluence, solve } from './solver.mjs';

class SeededRandom {
  constructor(seed) { this.state = seed & 0x7fffffff; }
  nextInt(bound) {
    this.state = (Math.imul(1103515245, this.state) + 12345) & 0x7fffffff;
    return (this.state >> 12) % bound;
  }
  shuffle(items) {
    for (let index = items.length - 1; index > 0; index--) {
      const other = this.nextInt(index + 1);
      [items[index], items[other]] = [items[other], items[index]];
    }
  }
}

export function puzzleSeed(id) {
  let hash = 0x011c9dc5;
  for (let i = 0; i < id.length; i++) {
    hash = Math.imul(hash ^ id.charCodeAt(i), 0x01000193) & 0x7fffffff;
  }
  return hash;
}

export function generatePuzzle(request, { level = 0 } = {}) {
  let best = null;
  let distance = 1 << 30;
  let certified = 0;
  const target = 30 + Math.round(level / 10);
  for (let attempt = 0; attempt < 24; attempt++) {
    const seed = attempt === 0 ? request.seed : puzzleSeed(`${request.seed}/${attempt}`);
    const board = tryGenerate({ size: request.size, seed, clues: request.clues }, level);
    if (!board) continue;
    if (level === 0) return board;
    const candidateDistance = Math.abs(difficultyScore(board) - target) - 8 * mechanicInfluence(board.puzzle);
    if (candidateDistance < distance) { best = board; distance = candidateDistance; }
    if (++certified === 2) return best;
  }
  if (best) return best;
  throw new Error('Could not certify this puzzle');
}

const pairKey = (a, b) => `${a},${b}`;

function tryGenerate({ size, seed, clues }, level) {
  const random = new SeededRandom(seed);
  const area = size * size;
  const route = [];
  for (let row = 0; row < size; row++) {
    for (let column = 0; column < size; column++) route.push(row * size + (row % 2 === 0 ? column : size - column - 1));
  }
  const neighbors = new Puzzle(size, [route[0], route[route.length - 1]]).neighbors;

  for (let turn = 0; turn < area * 12; turn++) {
    if (random.nextInt(2) === 0) route.reverse();
    const choices = neighbors[route[0]].filter((cell) => cell !== route[1]);
    if (choices.length === 0) continue;
    const join = route.indexOf(choices[random.nextInt(choices.length)]);
    const prefix = route.slice(0, join).reverse();
    prefix.forEach((cell, index) => { route[index] = cell; });
  }

  const pattern = level > 300 ? (level - 301) % 6 : -1;
  const wallEnabled = (level >= 31 && level <= 70) || (level >= 101 && level <= 120) ||
    (level >= 151 && level <= 180) || (level >= 231 && level <= 260) ||
    pattern === 0 || pattern === 3 || pattern === 5;
  const iceEnabled = (level >= 71 && level <= 120) || (level >= 181 && level <= 200) ||
    (level >= 261 && level <= 300) || pattern === 1 || pattern === 3 || pattern === 4 || pattern === 5;
  const gateEnabled = (level >= 121 && level <= 200) || pattern === 0 || pattern === 2 ||
    pattern === 4 || pattern === 5;
  const portalEnabled = (level >= 201 && level <= 300) || pattern === 1 || pattern === 2 ||
    pattern === 4 || pattern === 5;

  let portal = null;
  if (portalEnabled) {
    const splices = [];
    for (let i = 1; i < route.length - 4; i++) {
      for (let j = i + 2; j < route.length - 2; j++) {
        if (neighbors[route[i]].includes(route[j]) && !neighbors[route[i + 1]].includes(route[j + 1])) splices.push([i, j]);
      }
    }
    if (splices.length === 0) return null;
    const [i, j] = splices[random.nextInt(splices.length)];
    const reversed = route.slice(i + 1, j + 1).reverse();
    reversed.forEach((cell, index) => { route[i + 1 + index] = cell; });
    portal = [route[j], route[j + 1]];
  }

  const wallOptions = [];
  for (let i = 0; i < area; i++) {
    for (const neighbor of neighbors[route[i]]) {
      if (route[i] < neighbor && Math.abs(route.indexOf(neighbor) - i) !== 1) wallOptions.push([route[i], neighbor]);
    }
  }
  const walls = [];
  if (wallEnabled) {
    const allowed = new Set(wallOptions.map(([a, b]) => pairKey(a, b)));
    const runs = [];
    for (const [a, b] of wallOptions) {
      const stride = b - a === 1 ? size : 1;
      const run = [[a, b]];
      for (let step = 1; step <= 2; step++) {
        const next = [a + stride * step, b + stride * step];
        if ((stride === 1 && Math.floor(a / size) !== Math.floor(next[0] / size)) || !allowed.has(pairKey(...next))) break;
        run.push(next);
      }
      if (run.length >= 2) runs.push(run);
    }
    if (runs.length === 0) return null;
    walls.push(...runs[random.nextInt(runs.length)]);
  }

  let gate = null;
  if (gateEnabled) {
    const end = [...route].reverse().slice(2).find((cell) => !portal || (cell !== portal[0] && cell !== portal[1]));
    if (end === undefined) throw new Error('No gate cell available');
    gate = [route[2], end];
  }

  const ice = [];
  const reserved = new Set();
  if (portal) { reserved.add(portal[0]); reserved.add(portal[1]); }
  if (gate) { reserved.add(gate[0]); reserved.add(gate[1]); }
  if (iceEnabled) {
    const straight = [];
    for (let i = 1; i < area - 1; i++) {
      if (neighbors[route[i - 1]].includes(route[i]) && neighbors[route[i]].includes(route[i + 1]) &&
          route[i] - route[i - 1] === route[i + 1] - route[i] && !reserved.has(route[i])) straight.push(route[i]);
    }
    if (straight.length === 0) return null;
    if (straight.length < 2) return null;
    const pairs = [];
    for (let i = 0; i < straight.length - 1; i++) {
      if (route.indexOf(straight[i + 1]) === route.indexOf(straight[i]) + 1) pairs.push([straight[i], straight[i + 1]]);
    }
    if (pairs.length > 0) {
      ice.push(...pairs[random.nextInt(pairs.length)]);
    } else {
      random.shuffle(straight);
      ice.push(...straight.slice(0, 2));
    }
  }
  ice.forEach((cell) => reserved.add(cell));

  const build = (checkpoints) => new Puzzle(size, checkpoints, { walls, gate, portal, iceTiles: ice });

  let puzzle = build(route.filter((cell) => !reserved.has(cell)));
  let proof = solve(puzzle);
  if (!proof.unique) return null;
  const removable = route.slice(1, area - 1);
  random.shuffle(removable);
  const limit = Math.min(Math.max(clues, 2), area);
  for (const cell of removable) {
    if (puzzle.checkpoints.length <= limit) break;
    if (!puzzle.checkpoints.includes(cell)) continue;
    const candidate = build(puzzle.checkpoints.filter((value) => value !== cell));
    const result = solve(candidate, { budget: 18000 });
    if (result.unique) { puzzle = candidate; proof = result; }
  }
  return { puzzle, solution: proof.first };
}
