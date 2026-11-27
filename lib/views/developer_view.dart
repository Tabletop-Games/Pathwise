import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../cloud/cloud_sync_service.dart';
import '../logic/game_state_storage.dart';
import '../logic/haptic_service.dart';
import '../logic/notification_service.dart';
import '../logic/puzzle.dart';
import '../logic/puzzle_generator.dart';
import '../logic/sound_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import '../model/progression.dart';
import '../ui/game_ui.dart';
import 'main_menu_view.dart';
import 'puzzle_view.dart';

VerifiedPuzzle _generateForSolutionViewer(
  ({int level, ({int size, int seed, int clues}) gen}) args,
) => generatePuzzle(args.gen, level: args.level);

class DeveloperView extends StatefulWidget {
  const DeveloperView({super.key});

  @override
  State<DeveloperView> createState() => _DeveloperViewState();
}

class _DeveloperViewState extends State<DeveloperView> {
  final _levelInput = TextEditingController(text: '1');
  final _coinsInput = TextEditingController(text: '500');
  final _hintsInput = TextEditingController(text: '5');
  final _seedInput = TextEditingController(text: '1');

  String? _statusMessage;
  int _previewSize = 5;
  int _mechanicLevel = 0;
  int _seed = 1;
  int _clueFactor = 2;
  VerifiedPuzzle? _generated;

  void _setStatus(String message) {
    if (!mounted) return;
    setState(() => _statusMessage = message);
  }

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
        _statusMessage =
            'Certified unique · seed $seed · ${active.isEmpty ? 'Classic' : active.join(', ')} · ${board.solution.length} cells';
      });
    } catch (error) {
      setState(() {
        _generated = null;
        _statusMessage = 'Generation failed for seed $seed: $error';
      });
    }
  }

  Future<void> _openSolutionViewer({VerifiedPuzzle? customBoard}) async {
    if (customBoard != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _CertifiedSolutionView(
            title: 'Generated Seed $_seed',
            preloaded: customBoard,
            seed: _seed,
          ),
        ),
      );
      return;
    }
    final level = int.tryParse(_levelInput.text.trim());
    if (level == null || level < 1) {
      _setStatus('Enter a valid level number (>= 1) to inspect its solution.');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _CertifiedSolutionView(
          title: 'Level $level Certified Solution',
          level: level,
          seed: PuzzleId.level(level).generation.seed,
        ),
      ),
    );
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
    _levelInput.dispose();
    _coinsInput.dispose();
    _hintsInput.dispose();
    _seedInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    if (!model.developerMode) return const SizedBox.shrink();
    final p = context.palette;
    final cloud = context.watch<CloudSyncService?>();
    final notifications = context.watch<NotificationService?>();

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
            child: Text(
              title,
              style: TextStyle(
                color: p.mutedInk,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ),
          GameCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Developer dashboard')),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                children: [
                  if (_statusMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GameCard(
                        padding: const EdgeInsets.all(12),
                        selected: true,
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                _statusMessage!,
                                style: TextStyle(
                                  color: p.ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Dismiss',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  setState(() => _statusMessage = null),
                            ),
                          ],
                        ),
                      ),
                    ),
                  section('Overview', [
                    _kv('Build mode', kDebugMode ? 'Debug' : 'Profile/Release'),
                    _kv('Current level', '${model.highestUnlocked}'),
                    _kv(
                      'Solved / Stars',
                      '${model.solved} / ${model.campaignStarStats.totalStars}',
                    ),
                    _kv('Test date', model.todayKey),
                    _kv(
                      'Streak',
                      '${model.streak.count} days (${model.streak.freezes} freezes)',
                    ),
                  ]),
                  section('Puzzle tools', [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _levelInput,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Campaign level',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            final level = int.tryParse(_levelInput.text.trim());
                            if (level == null || level < 1) {
                              _setStatus('Enter a valid level (>= 1).');
                              return;
                            }
                            openPuzzle(context, PuzzleId.level(level));
                          },
                          child: const Text('Open'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      onPressed: () => _openSolutionViewer(),
                      label: const Text('Inspect certified solution'),
                    ),
                    const Divider(height: 20),
                    Text(
                      'Custom puzzle generator',
                      style: TextStyle(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final size in [4, 5, 6, 7])
                          ChoiceChip(
                            label: Text('$size×$size'),
                            selected: _previewSize == size,
                            onSelected: (_) =>
                                setState(() => _previewSize = size),
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
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
                            onSelected: (_) =>
                                setState(() => _mechanicLevel = level),
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final (name, factor) in [
                          ('Sparse', 1),
                          ('Standard', 2),
                          ('Guided', 3),
                        ])
                          ChoiceChip(
                            label: Text(name),
                            selected: _clueFactor == factor,
                            onSelected: (_) =>
                                setState(() => _clueFactor = factor),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _seedInput,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Seed',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            final seed = int.tryParse(_seedInput.text.trim());
                            if (seed == null) {
                              _setStatus('Enter a numeric seed.');
                              return;
                            }
                            _generate(seed);
                          },
                          child: const Text('Generate'),
                        ),
                      ],
                    ),
                    if (_generated case final board?) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton(
                            onPressed: () => _play(board),
                            child: const Text('Play'),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              _seedInput.text = '${_seed + 1}';
                              _generate(_seed + 1);
                            },
                            child: const Text('Next seed'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                _openSolutionViewer(customBoard: board),
                            child: const Text('View solution'),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: '$_seed'));
                              _setStatus('Copied seed $_seed to clipboard.');
                            },
                            child: const Text('Copy seed'),
                          ),
                        ],
                      ),
                    ],
                  ]),
                  section('Economy & progression', [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _coinsInput,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Coins',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            final coins = int.tryParse(_coinsInput.text.trim());
                            if (coins == null || coins < 0) {
                              _setStatus('Enter a valid coin amount (>= 0).');
                              return;
                            }
                            model.setDebugResources(coins: coins);
                            _setStatus('Coins set to $coins.');
                          },
                          child: const Text('Set coins'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _hintsInput,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Hints',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            final hints = int.tryParse(_hintsInput.text.trim());
                            if (hints == null || hints < 0) {
                              _setStatus('Enter a valid hint count (>= 0).');
                              return;
                            }
                            model.setDebugResources(hints: hints);
                            _setStatus('Hints set to $hints.');
                          },
                          child: const Text('Set hints'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        model.grantDebugProgression();
                        _setStatus(
                          'Unlocked Research & granted Boosts/Freezes.',
                        );
                      },
                      child: const Text(
                        'Unlock Research & grant Boosts / Freezes',
                      ),
                    ),
                  ]),
                  section('Time & streak testing', [
                    _kv('Current test date', model.todayKey),
                    _kv('Daily solved today', '${model.dailySolvedToday}'),
                    _kv(
                      'Streak qualified today',
                      '${model.streakQualifiedToday}',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        OutlinedButton(
                          onPressed: () => model.advanceDebugDay(qualify: true),
                          child: const Text('Simulate qualifying day'),
                        ),
                        OutlinedButton(
                          onPressed: model.advanceDebugDay,
                          child: const Text('Skip to next day'),
                        ),
                      ],
                    ),
                  ]),
                  section('Ads & rewards simulation', [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final (label, action)
                            in <(String, Future<bool> Function(String))>[
                              ('Coin video', model.grantAdBonus),
                              ('Hint video', model.grantHintAd),
                              (
                                '3× boost video',
                                (k) =>
                                    model.grantBoostAd(Boost.tripleFifteen, k),
                              ),
                              (
                                '2× boost video',
                                (k) => model.grantBoostAd(Boost.doubleTen, k),
                              ),
                            ])
                          OutlinedButton(
                            onPressed: () async {
                              final granted = await action(
                                'debug-${DateTime.now().microsecondsSinceEpoch}',
                              );
                              _setStatus(
                                granted
                                    ? 'Simulated reward granted: $label'
                                    : 'Simulated reward declined: $label',
                              );
                            },
                            child: Text(label),
                          ),
                      ],
                    ),
                  ]),
                  section('Audio & haptics', [
                    _kv(
                      'Sound',
                      model.soundEnabled
                          ? '${(model.soundVolume * 100).round()}%'
                          : 'Muted',
                    ),
                    _kv('Haptics', model.haptics ? 'Enabled' : 'Disabled'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.volume_up_outlined, size: 18),
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const _TestSoundsView(),
                            ),
                          ),
                          label: const Text('Test Sounds'),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.vibration_rounded, size: 18),
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const _TestHapticsView(),
                            ),
                          ),
                          label: const Text('Test Haptics'),
                        ),
                      ],
                    ),
                  ]),
                  if (notifications != null)
                    section('Notifications', [
                      _kv(
                        'Permission',
                        notifications.permissionGranted ? 'Granted' : 'Denied',
                      ),
                      _kv(
                        'Scheduled count',
                        '${notifications.scheduled.length}',
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(
                          Icons.notifications_active_outlined,
                          size: 18,
                        ),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const _NotificationDebugView(),
                          ),
                        ),
                        label: const Text('Notification diagnostics & tests'),
                      ),
                    ]),
                  section('Diagnostics', [
                    _kv(
                      'Cloud sync',
                      cloud == null ? 'Unavailable' : cloud.status.name,
                    ),
                    _kv('Online ready', '${model.onlineReady}'),
                    _kv('Storage error', '${model.storageError}'),
                    _kv(
                      'Owned themes / tips',
                      '${model.ownedThemes} / ${model.ownedTipsCount}',
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _CertifiedSolutionView extends StatefulWidget {
  const _CertifiedSolutionView({
    required this.title,
    this.level,
    this.preloaded,
    required this.seed,
  });

  final String title;
  final int? level;
  final VerifiedPuzzle? preloaded;
  final int seed;

  @override
  State<_CertifiedSolutionView> createState() => _CertifiedSolutionViewState();
}

class _CertifiedSolutionViewState extends State<_CertifiedSolutionView> {
  VerifiedPuzzle? _board;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.preloaded != null) {
      _board = widget.preloaded;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final level = widget.level!;
      final board = await compute(_generateForSolutionViewer, (
        level: level,
        gen: PuzzleId.level(level).generation,
      ));
      if (!mounted) return;
      setState(() {
        _board = board;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to generate certified solution: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: GameCard(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!),
                      ),
                    )
                  : _buildContent(context, _board!, palette),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    VerifiedPuzzle board,
    BoardPalette palette,
  ) {
    final puzzle = board.puzzle;
    final mechanics = [
      if (puzzle.walls.isNotEmpty) 'Walls (${puzzle.walls.length})',
      if (puzzle.arrow != null) 'One-way arrow',
      if (puzzle.gate != null) 'Key & gate',
      if (puzzle.portal != null) 'Portal',
      if (puzzle.iceTiles.isNotEmpty) 'Ice (${puzzle.iceTiles.length})',
    ];
    final summary =
        '${widget.title}\n'
        'Size: ${puzzle.size}x${puzzle.size} | Seed: ${widget.seed}\n'
        'Mechanics: ${mechanics.isEmpty ? 'Classic' : mechanics.join(', ')}\n'
        'Checkpoints: ${puzzle.checkpoints.join(' -> ')}\n'
        'Solution (${board.solution.length} cells): ${board.solution.join(' -> ')}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GameCard(
          padding: const EdgeInsets.all(14),
          child: AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              painter: _SolutionBoardPainter(
                puzzle: puzzle,
                solution: board.solution,
                palette: palette,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GameCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${puzzle.size}×${puzzle.size} · Seed ${widget.seed}',
                style: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Mechanics: ${mechanics.isEmpty ? 'Classic' : mechanics.join(', ')}',
                style: TextStyle(color: palette.mutedInk, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                'Checkpoints: ${puzzle.checkpoints.join(' → ')}',
                style: TextStyle(color: palette.ink, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SelectableText(
                board.solution.join(' → '),
                style: TextStyle(color: palette.mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 10),
              ActionPill(
                label: 'Copy solution info',
                icon: Icons.copy_rounded,
                tone: ActionTone.primary,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: summary));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied solution details.')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SolutionBoardPainter extends CustomPainter {
  const _SolutionBoardPainter({
    required this.puzzle,
    required this.solution,
    required this.palette,
  });

  final Puzzle puzzle;
  final List<int> solution;
  final BoardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width / puzzle.size;
    final tilePaint = Paint()..color = palette.tile;
    final borderPaint = Paint()
      ..color = palette.cardEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var cell = 0; cell < puzzle.area; cell++) {
      final rect = Rect.fromLTWH(
        (cell % puzzle.size) * side + 2,
        (cell ~/ puzzle.size) * side + 2,
        side - 4,
        side - 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(side * 0.14)),
        tilePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(side * 0.14)),
        borderPaint,
      );
    }

    Offset centerOf(int cell) => Offset(
      (cell % puzzle.size + 0.5) * side,
      (cell ~/ puzzle.size + 0.5) * side,
    );

    final routePaint = Paint()
      ..color = palette.route
      ..strokeWidth = side * 0.24
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (var i = 0; i < solution.length; i++) {
      final p = centerOf(solution[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        final prev = solution[i - 1];
        final cur = solution[i];
        final isPortal =
            puzzle.portal != null &&
            ((puzzle.portal!.$1 == prev && puzzle.portal!.$2 == cur) ||
                (puzzle.portal!.$2 == prev && puzzle.portal!.$1 == cur));
        if (isPortal) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }
    canvas.drawPath(path, routePaint);

    for (var cell = 0; cell < puzzle.area; cell++) {
      final number = puzzle.numbers[cell];
      if (number == 0) continue;
      final c = centerOf(cell);
      canvas.drawCircle(c, side * 0.24, Paint()..color = palette.accent);
      final tp = TextPainter(
        text: TextSpan(
          text: '$number',
          style: TextStyle(
            color: palette.onAccent,
            fontWeight: FontWeight.w800,
            fontSize: side * 0.24,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_SolutionBoardPainter old) =>
      old.puzzle != puzzle || old.palette != palette;
}

class _TestSoundsView extends StatefulWidget {
  const _TestSoundsView();

  @override
  State<_TestSoundsView> createState() => _TestSoundsViewState();
}

class _TestSoundsViewState extends State<_TestSoundsView> {
  late final AppModel _model;
  late final bool _origEnabled;
  late final double _origVolume;
  double _previewVolume = 0.75;
  bool _overrideMute = true;
  SoundEvent? _activeEvent;
  Timer? _sequenceTimer;
  int _sequenceIndex = 0;

  @override
  void initState() {
    super.initState();
    _model = context.read<AppModel>();
    _origEnabled = _model.sound.enabled;
    _origVolume = _model.sound.volume;
    _previewVolume = _origVolume;
  }

  @override
  void dispose() {
    _sequenceTimer?.cancel();
    _model.sound.enabled = _origEnabled;
    _model.sound.volume = _origVolume;
    super.dispose();
  }

  void _playSingle(SoundEvent event) {
    _model.sound.enabled = _overrideMute ? true : _origEnabled;
    _model.sound.volume = _previewVolume;
    _model.sound.play(event);
    setState(() => _activeEvent = event);
  }

  void _togglePlayAll() {
    if (_sequenceTimer != null) {
      _sequenceTimer?.cancel();
      _sequenceTimer = null;
      setState(() => _activeEvent = null);
      return;
    }
    _sequenceIndex = 0;
    const events = SoundEvent.values;
    _playSingle(events[_sequenceIndex++]);
    _sequenceTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted || _sequenceIndex >= events.length) {
        timer.cancel();
        _sequenceTimer = null;
        if (mounted) setState(() => _activeEvent = null);
        return;
      }
      _playSingle(events[_sequenceIndex++]);
    });
  }

  static String _labelFor(SoundEvent event) => switch (event) {
    SoundEvent.button => 'Button tap',
    SoundEvent.tab => 'Tab switch',
    SoundEvent.toggle => 'Settings toggle',
    SoundEvent.dialogOpen => 'Dialog open',
    SoundEvent.error => 'Action rejected / error',
    SoundEvent.step => 'Path step',
    SoundEvent.retract => 'Backtrack / undo',
    SoundEvent.checkpoint => 'Checkpoint reached',
    SoundEvent.ice => 'Ice slide',
    SoundEvent.portal => 'Portal warp',
    SoundEvent.keyCollected => 'Key collected',
    SoundEvent.gateUnlocked => 'Gate unlocked',
    SoundEvent.invalidMove => 'Invalid move',
    SoundEvent.hint => 'Hint used',
    SoundEvent.puzzleComplete => 'Puzzle complete',
    SoundEvent.countdown => 'Time Attack countdown',
    SoundEvent.attackFinished => 'Time Attack finished',
    SoundEvent.starReveal => 'Star reveal',
    SoundEvent.coinReward => 'Coin reward',
    SoundEvent.multiplierStop => 'Multiplier stop',
    SoundEvent.mysteryReveal => 'Mystery reward reveal',
    SoundEvent.treasure => 'Chapter / crate treasure',
    SoundEvent.wheelTick => 'Fortune Wheel tick',
    SoundEvent.wheelResult => 'Fortune Wheel result',
    SoundEvent.research => 'Research upgrade',
    SoundEvent.boost => 'Boost activated',
    SoundEvent.cosmetic => 'Cosmetic equipped / bought',
    SoundEvent.celebrate => 'Achievement / streak celebrate',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final playingAll = _sequenceTimer != null;
    final groups = [
      (
        'UI Interactions',
        [
          SoundEvent.button,
          SoundEvent.tab,
          SoundEvent.toggle,
          SoundEvent.dialogOpen,
          SoundEvent.error,
        ],
      ),
      (
        'Gameplay',
        [
          SoundEvent.step,
          SoundEvent.retract,
          SoundEvent.checkpoint,
          SoundEvent.ice,
          SoundEvent.portal,
          SoundEvent.keyCollected,
          SoundEvent.gateUnlocked,
          SoundEvent.invalidMove,
          SoundEvent.hint,
          SoundEvent.puzzleComplete,
          SoundEvent.countdown,
          SoundEvent.attackFinished,
        ],
      ),
      (
        'Rewards & Progression',
        [
          SoundEvent.starReveal,
          SoundEvent.coinReward,
          SoundEvent.multiplierStop,
          SoundEvent.mysteryReveal,
          SoundEvent.treasure,
          SoundEvent.wheelTick,
          SoundEvent.wheelResult,
          SoundEvent.research,
          SoundEvent.boost,
          SoundEvent.cosmetic,
          SoundEvent.celebrate,
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Test Sounds')),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                children: [
                  GameCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Preview volume: ${(_previewVolume * 100).round()}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            ActionPill(
                              label: playingAll ? 'Stop' : 'Play All',
                              icon: playingAll
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                              tone: ActionTone.primary,
                              onTap: _togglePlayAll,
                            ),
                          ],
                        ),
                        Slider(
                          value: _previewVolume,
                          onChanged: (v) => setState(() => _previewVolume = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Temporary unmute override'),
                          subtitle: const Text(
                            'Original sound preferences are restored on exit.',
                          ),
                          value: _overrideMute,
                          onChanged: (v) => setState(() => _overrideMute = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final (groupTitle, events) in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                      child: Text(
                        groupTitle,
                        style: TextStyle(
                          color: palette.mutedInk,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    GameCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < events.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, color: palette.cardEdge),
                            ListTile(
                              title: Text(_labelFor(events[i])),
                              subtitle: Text(
                                events[i].name,
                                style: TextStyle(
                                  color: palette.mutedInk,
                                  fontSize: 12,
                                ),
                              ),
                              selected: _activeEvent == events[i],
                              trailing: IconButton(
                                tooltip: 'Play ${_labelFor(events[i])}',
                                icon: const Icon(
                                  Icons.play_circle_outline_rounded,
                                ),
                                onPressed: () => _playSingle(events[i]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TestHapticsView extends StatelessWidget {
  const _TestHapticsView();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = context.palette;

    void fireHaptic(HapticEvent event) {
      final wasEnabled = model.haptic.enabled;
      model.haptic.enabled = true;
      model.haptic.trigger(event);
      model.haptic.enabled = wasEnabled;
    }

    void fireCombined(HapticEvent haptic, SoundEvent sound) {
      fireHaptic(haptic);
      final wasSound = model.sound.enabled;
      model.sound.enabled = true;
      model.sound.play(sound);
      model.sound.enabled = wasSound;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Test Haptics')),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                children: [
                  GameCard(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Triggers every semantic HapticEvent directly without modifying saves or balances. Note: physical vibration quality can only be evaluated on a real Android device.',
                      style: TextStyle(color: palette.mutedInk, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GameCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Combined Sound + Haptic',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final (label, h, s) in const [
                              ('Step', HapticEvent.step, SoundEvent.step),
                              (
                                'Checkpoint',
                                HapticEvent.checkpoint,
                                SoundEvent.checkpoint,
                              ),
                              (
                                'Invalid move',
                                HapticEvent.invalidMove,
                                SoundEvent.invalidMove,
                              ),
                              (
                                'Complete',
                                HapticEvent.puzzleComplete,
                                SoundEvent.puzzleComplete,
                              ),
                              (
                                'Reward',
                                HapticEvent.treasure,
                                SoundEvent.treasure,
                              ),
                            ])
                              ActionPill(
                                label: label,
                                onTap: () => fireCombined(h, s),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GameCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < HapticEvent.values.length; i++) ...[
                          if (i > 0)
                            Divider(height: 1, color: palette.cardEdge),
                          ListTile(
                            title: Text(HapticEvent.values[i].name),
                            trailing: IconButton(
                              tooltip: 'Trigger ${HapticEvent.values[i].name}',
                              icon: const Icon(Icons.vibration_rounded),
                              onPressed: () =>
                                  fireHaptic(HapticEvent.values[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationDebugView extends StatelessWidget {
  const _NotificationDebugView();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final notifications = context.watch<NotificationService?>();
    final palette = context.palette;
    if (notifications == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notification Diagnostics')),
        body: const Center(child: Text('NotificationService unavailable.')),
      );
    }
    final prefs = model.notificationPreferences;
    final learnedMins = notifications.adaptiveMinutesFor(prefs);
    final learnedTime = TimeOfDay(
      hour: learnedMins ~/ 60,
      minute: learnedMins % 60,
    ).format(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Diagnostics')),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                children: [
                  GameCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Permission: ${notifications.permissionGranted ? "Granted" : "Denied"}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text('Master enabled: ${prefs.enabled}'),
                        Text(
                          'Adaptive timing: ${prefs.adaptiveTiming} ($learnedTime)',
                        ),
                        Text(
                          'Recorded sessions: ${prefs.activityTimestamps.length}',
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            ActionPill(
                              label: 'Request permission',
                              onTap: () => notifications.requestPermission(),
                            ),
                            ActionPill(
                              label: 'Android settings',
                              onTap: notifications.openSystemSettings,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GameCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Test delivery (isolated test IDs)',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final cat in NotificationCategory.values)
                              ActionPill(
                                label: 'Now: ${cat.name}',
                                onTap: () => notifications.sendTestNow(cat),
                              ),
                            ActionPill(
                              label: 'In 5s (daily)',
                              tone: ActionTone.primary,
                              onTap: () => notifications.scheduleTestDelayed(
                                NotificationCategory.daily,
                              ),
                            ),
                            ActionPill(
                              label: 'Cancel tests',
                              onTap: notifications.cancelTestNotifications,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GameCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scheduled reminders (${notifications.scheduled.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        if (notifications.scheduled.isEmpty)
                          Text(
                            'No reminders currently scheduled.',
                            style: TextStyle(color: palette.mutedInk),
                          )
                        else
                          for (final item in notifications.scheduled)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '[${item.category.name}] #${item.id} @ ${item.scheduledAt}\n${item.title} — ${item.body}',
                                style: TextStyle(
                                  color: palette.ink,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewStorage extends GameStateStorage {
  @override
  Future<void> save(String snapshot) async {}
}
