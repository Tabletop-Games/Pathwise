import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/game_state_storage.dart';
import '../logic/puzzle.dart';
import '../logic/puzzle_generator.dart';
import '../model/app_model.dart';
import '../model/game_state.dart';
import '../model/progression.dart';
import 'main_menu_view.dart';
import 'puzzle_view.dart';

class DeveloperView extends StatefulWidget {
  const DeveloperView({super.key});

  @override
  State<DeveloperView> createState() => _DeveloperViewState();
}

class _DeveloperViewState extends State<DeveloperView> {
  final _input = TextEditingController(text: '1');
  String? _result;
  int _previewSize = 5;
  int _mechanicLevel = 0;
  int _seed = 0;
  int _clueFactor = 2;
  VerifiedPuzzle? _generated;

  void _generate(int seed) {
    try {
      final board = generatePuzzle((
        size: _previewSize,
        seed: seed,
        clues: _previewSize * _clueFactor,
      ), level: _mechanicLevel);
      final puzzle = board.puzzle;
      final active = [
        if (puzzle.walls.isNotEmpty) 'Walls',
        if (puzzle.arrow != null) 'One-way',
        if (puzzle.gate != null) 'Keys',
        if (puzzle.portal != null) 'Portals',
        if (puzzle.iceTiles.isNotEmpty) 'Ice',
      ];
      setState(() {
        _seed = seed;
        _generated = board;
        _result =
            'Certified unique · seed $seed\n${active.isEmpty ? 'Classic' : active.join(', ')} · ${board.solution.length} cells';
      });
    } catch (error) {
      setState(() {
        _generated = null;
        _result = 'Generation failed for seed $seed. $error';
      });
    }
  }

  Future<void> _play(VerifiedPuzzle board) async {
    final preview = AppModel(
      storage: _PreviewStorage(),
      snapshot: const {},
      loader: (_) async => board,
    );
    await preview.open(const PuzzleId.level(1));
    if (mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: preview,
            child: const PuzzleView(),
          ),
        ),
      );
    }
    preview.dispose();
  }

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
              final board = generatePuzzle(
                PuzzleId.level(level).generation,
                level: level,
              );
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
          Text('Test date: ${model.todayKey}'),
          OutlinedButton(
            onPressed: () => model.advanceDebugDay(qualify: true),
            child: const Text('Simulate next qualifying day'),
          ),
          OutlinedButton(
            onPressed: model.advanceDebugDay,
            child: const Text('Skip to next day'),
          ),
          OutlinedButton(
            onPressed: model.grantDebugProgression,
            child: const Text('Unlock Research and grant Boosts and Freezes'),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final size in [4, 5, 6, 7])
                ChoiceChip(
                  label: Text('$size×$size'),
                  selected: _previewSize == size,
                  onSelected: (_) => setState(() => _previewSize = size),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final (label, level) in [
                ('Classic', 0),
                ('Walls', 21),
                ('Keys', 71),
                ('Portals', 101),
                ('Ice', 151),
                ('Mixed', 201),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _mechanicLevel == level,
                  onSelected: (_) => setState(() => _mechanicLevel = level),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final (name, factor) in [
                ('Sparse', 1),
                ('Standard', 2),
                ('Guided', 3),
              ])
                ChoiceChip(
                  label: Text(name),
                  selected: _clueFactor == factor,
                  onSelected: (_) => setState(() => _clueFactor = factor),
                ),
            ],
          ),
          FilledButton(
            onPressed: () {
              if (int.tryParse(_input.text) case final seed?) _generate(seed);
            },
            child: const Text('Generate'),
          ),
          if (_generated case final board?)
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _play(board),
                  child: const Text('Play'),
                ),
                OutlinedButton(
                  onPressed: () => _generate(_seed + 1),
                  child: const Text('Regenerate'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      setState(() => _result = board.solution.join(' → ')),
                  child: const Text('Show solution'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: '$_seed')),
                  child: const Text('Copy seed'),
                ),
              ],
            ),
          for (final (label, action)
              in <(String, Future<bool> Function(String))>[
                ('Simulate earned coin video', model.grantAdBonus),
                ('Simulate earned hint video', model.grantHintAd),
                (
                  'Simulate earned 3× boost video',
                  (key) => model.grantBoostAd(Boost.tripleFifteen, key),
                ),
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

class _PreviewStorage extends GameStateStorage {
  @override
  Future<void> save(String snapshot) async {}
}
