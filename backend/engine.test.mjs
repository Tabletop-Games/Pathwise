import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildPuzzle, parsePuzzleKey } from './engine/ids.mjs';
import { puzzleSeed } from './engine/generator.mjs';
import { Puzzle, isValidPath, validateCompletedRoute } from './engine/puzzle.mjs';
import { solve } from './engine/solver.mjs';

test('puzzle keys map to the same generation requests as the Flutter app', () => {
  assert.deepEqual(parsePuzzleKey('levels/1').request, { size: 4, seed: puzzleSeed('pathwise-catalogue-v3/levels/1'), clues: 8 });
  assert.equal(parsePuzzleKey('levels/1000').request.clues, 14);
  assert.equal(parsePuzzleKey('levels/1001'), null);
  assert.equal(parsePuzzleKey('levels/0'), null);
  assert.equal(parsePuzzleKey('daily/2026-02-30'), null);
  assert.equal(parsePuzzleKey('daily-checkpoint/2026-11-24/3'), null);
  assert.equal(parsePuzzleKey('daily-checkpoint/2026-11-24/2').size, 5);
  assert.equal(parsePuzzleKey('daily/2026-11-24').size, 6);
  assert.equal(parsePuzzleKey('attack/v2-abcdefgh12/9').size, 7);
  assert.equal(parsePuzzleKey('attack/legacy/1'), null);
  assert.equal(parsePuzzleKey({}), null);
});

test('seed hash is stable and stays in 31 bits', () => {
  assert.equal(puzzleSeed(''), 0x011c9dc5);
  assert.ok(puzzleSeed('pathwise-catalogue-v3/levels/42') <= 0x7fffffff);
  assert.equal(puzzleSeed('a'), puzzleSeed('a'));
});

test('catalogue boards are deterministic, uniquely solvable and match published clue counts', () => {
  const expected = { 4: 8, 5: 11 };
  for (const level of [1, 2, 30, 31, 70, 100, 101, 150, 201, 250, 301, 306, 1000]) {
    const parsed = parsePuzzleKey(`levels/${level}`);
    const board = buildPuzzle(parsed);
    assert.ok(validateCompletedRoute(board.puzzle, board.solution), `level ${level}`);
    assert.ok(solve(board.puzzle).unique, `level ${level} unique`);
    assert.equal(board.puzzle.size, parsed.size);
    if (expected[board.puzzle.size] && level <= 100) assert.equal(board.puzzle.checkpoints.length, expected[board.puzzle.size]);
  }
  const again = buildPuzzle(parsePuzzleKey('levels/150'));
  assert.deepEqual(again.puzzle.checkpoints, buildPuzzle(parsePuzzleKey('levels/150')).puzzle.checkpoints);
});

test('mechanics appear in the documented level bands', () => {
  const mech = (level) => buildPuzzle(parsePuzzleKey(`levels/${level}`)).puzzle;
  assert.equal(mech(10).walls.length + mech(10).iceTiles.size + (mech(10).gate ? 1 : 0), 0);
  assert.ok(mech(40).walls.length >= 2);
  assert.ok(mech(80).iceTiles.size === 2);
  assert.ok(mech(130).gate !== null);
  assert.ok(mech(210).portal !== null);
});

const open3 = () => new Puzzle(3, [0, 8]);

test('route validation enforces adjacency, repeats and finish rules', () => {
  const puzzle = new Puzzle(3, [0, 2, 4, 8]);
  const good = [0, 1, 2, 5, 4, 3, 6, 7, 8];
  assert.ok(validateCompletedRoute(puzzle, good));
  assert.ok(!validateCompletedRoute(puzzle, [0, 1, 2, 5, 4, 3, 6, 7]));
  assert.ok(!validateCompletedRoute(puzzle, [0, 4, 2, 5, 4, 3, 6, 7, 8]));
  assert.ok(!validateCompletedRoute(puzzle, [0, 1, 2, 5, 8, 7, 6, 3, 4]), 'finish must be last');
  assert.ok(!validateCompletedRoute(puzzle, [0, 3, 6, 7, 4, 1, 2, 5, 8]), 'checkpoint order');
  assert.ok(!validateCompletedRoute(puzzle, 'route'));
  assert.ok(!isValidPath(open3(), [1, 2]));
  assert.ok(!isValidPath(open3(), [0, 1, 1]));
});

test('walls, gates, portals and ice follow the shared movement predicate', () => {
  const wall = new Puzzle(3, [0, 8], { walls: [[0, 1]] });
  assert.ok(!isValidPath(wall, [0, 1]));
  assert.ok(isValidPath(wall, [0, 3]));
  const gate = new Puzzle(3, [0, 8], { gate: [4, 5] });
  assert.ok(!isValidPath(gate, [0, 1, 2, 5]));
  assert.ok(isValidPath(gate, [0, 1, 4, 5]));
  const ice = new Puzzle(3, [0, 8], { iceTiles: [1] });
  assert.ok(isValidPath(ice, [0, 1, 2]));
  assert.ok(!isValidPath(ice, [0, 1, 4]));
  const portal = new Puzzle(3, [0, 8], { portal: [1, 7] });
  assert.ok(isValidPath(portal, [0, 1, 7]));
  assert.ok(!isValidPath(portal, [0, 1, 4]));
});
