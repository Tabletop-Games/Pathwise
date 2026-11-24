// Port of lib/logic/puzzle_solver.dart. Node accounting and iteration order
// must match the Dart solver because bounded budgets influence generation.
import { Puzzle } from './puzzle.mjs';

const bit = (index) => 1n << BigInt(index);

export function solve(puzzle, { budget = 120000 } = {}) {
  const area = puzzle.area;
  const full = (1n << BigInt(area)) - 1n;
  const masks = Array.from({ length: area }, (_, cell) =>
    puzzle.movesFrom(cell).reduce((mask, next) => mask | bit(next), 0n));
  const bits = Array.from({ length: area }, (_, cell) => bit(cell));
  const path = [puzzle.start];
  const dead = new Set();
  let count = 0;
  let visitedNodes = 0;
  let exhausted = true;
  let first = null;

  const canCover = (cell, remaining) => {
    let cells = remaining;
    for (let index = 0; index < area && cells !== 0n; index++) {
      if ((cells & bits[index]) === 0n) continue;
      cells ^= bits[index];
      const edges = masks[index] & (remaining | bits[cell]);
      if (edges === 0n || (index !== puzzle.finish && (edges & (edges - 1n)) === 0n)) return false;
    }
    let connected = bits[cell];
    let frontier = connected;
    for (let index = 0; index < area && frontier !== 0n;) {
      if ((frontier & bits[index]) === 0n) { index++; continue; }
      frontier ^= bits[index];
      const added = masks[index] & remaining & ~connected;
      connected |= added;
      frontier |= added;
      index = 0;
    }
    return (connected & remaining) === remaining;
  };

  const search = (cell, remaining, checkpoint) => {
    if (++visitedNodes > budget || count >= 2) { exhausted = false; return; }
    if (remaining === 0n) {
      count++;
      if (first === null) first = [...path];
      return;
    }
    const previous = path.length > 1 ? path[path.length - 2] : null;
    const state = `${cell}|${remaining}|${puzzle.iceTiles.has(cell) ? previous : 'n'}`;
    if (dead.has(state)) return;
    if (!canCover(cell, remaining)) { dead.add(state); return; }
    const before = count;
    const visited = (index) => (remaining & bits[index]) === 0n;
    for (const next of puzzle.movesFrom(cell)) {
      if ((remaining & bits[next]) === 0n ||
          !puzzle.canExtend(cell, next, path.length, checkpoint, { previous, hasVisited: visited })) continue;
      path.push(next);
      search(next, remaining ^ bits[next], checkpoint + (puzzle.numbers[next] === 0 ? 0 : 1));
      path.pop();
      if (!exhausted || count >= 2) return;
    }
    if (before === count) dead.add(state);
  };

  search(puzzle.start, full ^ bits[puzzle.start], 2);
  return { count, exhausted: exhausted && count < 2, first, nodes: visitedNodes,
    get unique() { return this.exhausted && this.count === 1; } };
}

export function difficultyScore(board) {
  const p = board.puzzle;
  const route = board.solution;
  let choices = 0, decisions = 0, turns = 0, checkpoint = 2;
  for (let i = 0; i < route.length - 1; i++) {
    const seen = new Set(route.slice(0, i + 1));
    const options = p.movesFrom(route[i]).filter((next) => !seen.has(next) &&
      p.canExtend(route[i], next, i + 1, checkpoint, {
        allowEarlyFinish: true, previous: i > 0 ? route[i - 1] : null, hasVisited: (c) => seen.has(c),
      })).length;
    if (options > 1) { decisions++; choices += options - 1; }
    if (i > 0 && route[i] - route[i - 1] !== route[i + 1] - route[i]) turns++;
    if (p.numbers[route[i + 1]] !== 0) checkpoint++;
  }
  const proof = solve(p);
  let effort = 0;
  for (let nodes = proof.nodes; nodes > 1; nodes = Math.trunc(nodes / 2)) effort++;
  const kinds = [p.walls.length > 0, p.iceTiles.size > 0, p.gate !== null, p.portal !== null, p.arrow !== null]
    .filter(Boolean).length;
  return decisions * 3 + choices * 2 + Math.trunc(turns / 3) + effort + kinds * kinds;
}

export function mechanicInfluence(p) {
  const without = ({ walls = false, ice = false, gate = false, portal = false }) => new Puzzle(p.size, p.checkpoints, {
    walls: walls ? [] : p.walls, iceTiles: ice ? [] : [...p.iceTiles],
    gate: gate ? null : p.gate, portal: portal ? null : p.portal, arrow: p.arrow,
  });
  const candidates = [];
  if (p.walls.length) candidates.push(without({ walls: true }));
  if (p.iceTiles.size) candidates.push(without({ ice: true }));
  if (p.gate) candidates.push(without({ gate: true }));
  if (p.portal) candidates.push(without({ portal: true }));
  return candidates.filter((candidate) => solve(candidate, { budget: 12000 }).count >= 2).length;
}
