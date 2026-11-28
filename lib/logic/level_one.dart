import 'engine/schedule.dart';
import 'puzzle.dart';
import 'puzzle_generator.dart';

/// Level 1, generated on first use and shared by the demo, the theme previews
/// and the first-clear shortcut. It is a small open board, so building it is
/// cheap.
final VerifiedPuzzle levelOneBoard = generatePuzzle(campaignSpec(1));
