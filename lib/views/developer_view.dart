import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/puzzle_generator.dart';
import '../model/app_model.dart';
import '../model/game_state.dart';
import '../model/progression.dart';
import 'main_menu_view.dart';

class DeveloperView extends StatefulWidget {
  const DeveloperView({super.key});

  @override
  State<DeveloperView> createState() => _DeveloperViewState();
}

class _DeveloperViewState extends State<DeveloperView> {
  final _input = TextEditingController(text: '1');
  String? _result;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    if (!model.developerMode) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('Developer dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _input,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Level or resource amount',
            ),
          ),
          FilledButton(
            onPressed: () {
              final level = int.tryParse(_input.text);
              if (level != null && level > 0) {
                openPuzzle(context, PuzzleId.level(level));
              }
            },
            child: const Text('Open level'),
          ),
          OutlinedButton(
            onPressed: () {
              final level = int.tryParse(_input.text);
              if (level == null || level < 1) return;
              final board = generatePuzzle(PuzzleId.level(level).generation);
              setState(
                () => _result =
                    'Certified ${board.puzzle.size}×${board.puzzle.size}\n${board.solution.join(' → ')}',
              );
            },
            child: const Text('Inspect certified solution'),
          ),
          OutlinedButton(
            onPressed: () =>
                model.setDebugResources(coins: int.tryParse(_input.text)),
            child: const Text('Set coins'),
          ),
          OutlinedButton(
            onPressed: () =>
                model.setDebugResources(hints: int.tryParse(_input.text)),
            child: const Text('Set hints'),
          ),
          for (final (label, action)
              in <(String, Future<bool> Function(String))>[
                ('Simulate earned coin video', model.grantAdBonus),
                ('Simulate earned hint video', model.grantHintAd),
                (
                  'Simulate earned 2× boost video',
                  (key) => model.grantBoostAd(Boost.doubleTen, key),
                ),
              ])
            OutlinedButton(
              onPressed: () async {
                final granted = await action(
                  'debug-${DateTime.now().microsecondsSinceEpoch}',
                );
                if (mounted)
                  setState(
                    () => _result = granted
                        ? 'Test reward saved'
                        : 'Test reward declined',
                  );
              },
              child: Text(label),
            ),
          if (_result case final result?) SelectableText(result),
        ],
      ),
    );
  }
}
