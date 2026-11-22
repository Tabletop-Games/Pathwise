import '../lib/logic/puzzle_generator.dart';
import '../lib/model/game_state.dart';

void main() {
  final levels = [1, 12, 36, 37, 100, 150, 500, 1000, 1000000];
  for (final level in levels) {
    final request = PuzzleId.level(level).generation;
    generatePuzzle(request);
    final samples = <int>[];
    var checkpoints = 0;
    for (var run = 0; run < 25; run++) {
      final time = Stopwatch()..start();
      final board = generatePuzzle(request);
      time.stop();
      samples.add(time.elapsedMicroseconds);
      checkpoints = board.puzzle.checkpoints.length;
    }
    samples.sort();
    String ms(int micros) => (micros / 1000).toStringAsFixed(2);
    print(
      'Level $level · ${request.size}×${request.size} · $checkpoints clues · '
      'p50 ${ms(samples[12])} ms · p95 ${ms(samples[23])} ms',
    );
  }
}
