// Port of lib/logic/puzzle.dart. Keep movement rules identical to the client.

export const MoveRejection = Object.freeze({
  finished: 'finished', adjacency: 'adjacency', wall: 'wall', arrow: 'arrow', gate: 'gate',
  portal: 'portal', ice: 'ice', checkpoint: 'checkpoint', finish: 'finish', revisit: 'revisit',
});

const pairKey = (a, b) => `${a},${b}`;

export class Puzzle {
  constructor(size, checkpoints, { walls = [], arrow = null, gate = null, portal = null, iceTiles = [] } = {}) {
    if (!Number.isInteger(size) || size < 2 || size > 7) throw new RangeError('Invalid size');
    this.size = size;
    this.checkpoints = Object.freeze([...checkpoints]);
    this.walls = [];
    this.wallKeys = new Set();
    for (const [a, b] of walls) {
      if (!this.wallKeys.has(pairKey(a, b))) {
        this.walls.push([a, b]);
        this.wallKeys.add(pairKey(a, b));
      }
    }
    this.arrow = arrow;
    this.gate = gate;
    this.portal = portal;
    this.iceTiles = new Set(iceTiles);
    if (this.checkpoints.length < 2 || new Set(this.checkpoints).size !== this.checkpoints.length ||
        this.checkpoints.some((cell) => !Number.isInteger(cell) || cell < 0 || cell >= this.area)) {
      throw new RangeError('Invalid checkpoints');
    }
    this.numbers = new Array(this.area).fill(0);
    this.checkpoints.forEach((cell, index) => { this.numbers[cell] = index + 1; });
    this.neighbors = Array.from({ length: this.area }, (_, cell) => {
      const row = Math.floor(cell / size);
      const column = cell % size;
      const list = [];
      if (row > 0) list.push(cell - size);
      if (column > 0) list.push(cell - 1);
      if (column + 1 < size) list.push(cell + 1);
      if (row + 1 < size) list.push(cell + size);
      return list;
    });
  }

  get area() { return this.size * this.size; }
  get start() { return this.checkpoints[0]; }
  get finish() { return this.checkpoints[this.checkpoints.length - 1]; }
  hasWall(a, b) { return this.wallKeys.has(pairKey(a, b)) || this.wallKeys.has(pairKey(b, a)); }

  forcedNext(previous, cell) {
    if (this.portal && this.portal[0] === cell) return this.portal[1];
    if (!this.iceTiles.has(cell) || previous === null || previous === undefined) return null;
    const nextX = 2 * (cell % this.size) - (previous % this.size);
    const nextY = 2 * Math.floor(cell / this.size) - Math.floor(previous / this.size);
    if (nextX < 0 || nextX >= this.size || nextY < 0 || nextY >= this.size) return -1;
    return nextY * this.size + nextX;
  }

  movesFrom(cell) {
    const moves = [...this.neighbors[cell]];
    const portal = this.portal;
    if (portal && portal[0] === cell && !this.neighbors[cell].includes(portal[1])) moves.push(portal[1]);
    if (portal && portal[1] === cell && !this.neighbors[cell].includes(portal[0])) moves.push(portal[0]);
    return moves;
  }

  rejectionFor(cell, next, length, checkpoint, { allowEarlyFinish = false, previous = null, hasVisited = null } = {}) {
    if (cell === this.finish) return MoveRejection.finished;
    if (!this.movesFrom(cell).includes(next)) return MoveRejection.adjacency;
    if (this.hasWall(cell, next)) return MoveRejection.wall;
    if (this.arrow && this.arrow[0] === cell && this.arrow[1] !== next) return MoveRejection.arrow;
    if (this.gate && this.gate[1] === next && !(hasVisited && hasVisited(this.gate[0]) === true)) {
      return MoveRejection.gate;
    }
    if (this.portal && this.portal[1] === next && this.portal[0] !== cell) return MoveRejection.portal;
    const forced = this.forcedNext(previous, cell);
    if (forced !== null && forced !== next) return MoveRejection.ice;
    const number = this.numbers[next];
    if (number !== 0 && number !== checkpoint) return MoveRejection.checkpoint;
    if (allowEarlyFinish && next === this.finish) return null;
    return (next === this.finish) === (length + 1 === this.area) ? null : MoveRejection.finish;
  }

  canExtend(cell, next, length, checkpoint, options = {}) {
    return this.rejectionFor(cell, next, length, checkpoint, options) === null;
  }
}

/**
 * Mirrors GameController._validPath: the path starts at the start cell and every
 * step obeys the movement rules (gates, ice, portals, checkpoint order, walls).
 */
export function isValidPath(puzzle, path) {
  if (!Array.isArray(path) || path.length === 0 || path.length > puzzle.area) return false;
  if (!path.every((cell) => Number.isInteger(cell) && cell >= 0 && cell < puzzle.area)) return false;
  if (path[0] !== puzzle.start || new Set(path).size !== path.length) return false;
  let checkpoint = 2;
  const seen = new Set([path[0]]);
  for (let index = 1; index < path.length; index++) {
    const ok = puzzle.canExtend(path[index - 1], path[index], index, checkpoint, {
      allowEarlyFinish: true, previous: index > 1 ? path[index - 2] : null, hasVisited: (cell) => seen.has(cell),
    });
    if (!ok) return false;
    if (puzzle.numbers[path[index]] !== 0) checkpoint++;
    seen.add(path[index]);
  }
  return true;
}

/** A completed route is a valid path covering every cell and ending on the finish. */
export function validateCompletedRoute(puzzle, route) {
  return Array.isArray(route) && route.length === puzzle.area &&
    route[route.length - 1] === puzzle.finish && isValidPath(puzzle, route);
}
