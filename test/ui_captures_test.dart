import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/logic/connectivity_service.dart';
import '../lib/logic/mechanic_tutorials.dart';
import '../lib/main.dart';
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/economy.dart' show Achievement;
import '../lib/model/game_state.dart';
import '../lib/model/journey.dart';
import '../lib/model/path_tips.dart';
import '../lib/model/progression.dart';
import '../lib/model/user_preferences.dart';
import '../lib/ui/art/control_art.dart';
import '../lib/ui/art/medallion_art.dart';
import '../lib/ui/art/research_art.dart';
import '../lib/ui/game_art.dart';
import '../lib/ui/journey_art.dart';
import '../lib/views/components/economy_navigation.dart';
import '../lib/views/components/puzzle_board.dart';
import '../lib/views/components/tip_art.dart';
import '../lib/views/connection_view.dart';
import '../lib/views/fortune_view.dart';
import '../lib/views/journey_rewards.dart';
import '../lib/views/levels_view.dart';
import '../lib/views/mechanic_tutorial_view.dart';
import '../lib/views/progression_view.dart';
import '../lib/views/puzzle_view.dart';
import '../lib/views/settings_view.dart';
import '../lib/views/store_view.dart';
import '../lib/views/streak_view.dart';
import 'app_model_test.dart' show MemoryStorage, complete, fixture;

/// Renders every screen on the six reference themes and checks that nothing
/// overflows or throws. When `PATHWISE_CAPTURE_DIR` is set it also writes a
/// PNG per screen and a contact sheet of every path tip, so the output can be
/// inspected.
final _captureDir = Platform.environment['PATHWISE_CAPTURE_DIR'];

class _PreviewAds extends AdService {
  @override
  bool get enabled => true;
  @override
  bool get videoReady => true;
}

const _themes = <String, PathwiseTheme>{
  'light': PathwiseTheme.field,
  'dark': PathwiseTheme.blackwater,
  'warm': PathwiseTheme.warmWalnut,
  'cool': PathwiseTheme.glacier,
  'amoled': PathwiseTheme.amoledCarbon,
  'contrast': PathwiseTheme.signal,
};

AppModel _model(PathwiseTheme theme, {int discoveryClears = 0}) => AppModel(
  storage: MemoryStorage(),
  snapshot: {
    'preferences': {'theme': theme.name},
    'ownedThemes': [theme.name],
    if (discoveryClears != 0) 'journey': {'clears': discoveryClears},
    'progressionBoot': 1,
    'ledger': [
      {
        'id': 'fixture',
        'label': 'Fixture',
        'amount': 95,
        'at': '2026-11-23T00:00:00Z',
      },
    ],
    'progression': {
      'serial': 2,
      'inventory': {'doubleTen': 1},
    },
  },
  bootTime: () => (boot: 1, milliseconds: 100),
  loader: (_) async => fixture(),
)..setHaptics(false);

Future<void> _snap(WidgetTester tester, GlobalKey key, String name) async {
  final dir = _captureDir;
  if (dir == null) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _shell(
  GlobalKey key,
  AppModel model,
  AdService ads,
  BillingService billing,
  Widget home,
) => RepaintBoundary(
  key: key,
  child: MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: model),
      ChangeNotifierProvider.value(value: ads),
      ChangeNotifierProvider.value(value: billing),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: BoardPalette.palettes[model.theme]!.theme,
      home: home,
    ),
  ),
);

Future<void> _screens(
  WidgetTester tester, {
  required PathwiseTheme theme,
  required String label,
  required Size size,
  double textScale = 1,
  Set<String>? only,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.runAsync(
    () => rootBundle.loadString('assets/data/fortune-prizes.json'),
  );
  final ads = AdService();
  final billing = BillingService(persist: (_) async => true);
  addTearDown(ads.dispose);
  addTearDown(billing.dispose);
  final key = GlobalKey();

  Future<void> shot(String name) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '$label $name');
    await _snap(tester, key, '$label-$name');
  }

  Future<void> screen(
    String name,
    Widget Function() home, {
    Future<void> Function()? after,
  }) async {
    if (only != null && !only.contains(name)) return;
    final model = _model(theme);
    await tester.pumpWidget(_shell(key, model, ads, billing, home()));
    await tester.pump(const Duration(milliseconds: 50));
    if (after != null) await after();
    await shot(name);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  }

  // Home and gameplay use the real app shell.
  if (only == null || only.contains('home') || only.contains('puzzle')) {
    final model = _model(theme);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ChangeNotifierProvider.value(
          value: model,
          child: const PathwiseApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (only == null || only.contains('home')) await shot('home');
    if (only == null || only.contains('puzzle')) {
      await tester.tap(find.text('Play level 1'));
      await tester.pumpAndSettle();
      await shot('puzzle');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  }

  Future<void> tab(String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  await screen('store-themes', () => const StoreView());
  await screen('store-tips', () => const StoreView(), after: () => tab('Tips'));
  await screen(
    'store-coins',
    () => const StoreView(),
    after: () => tab('Coins'),
  );
  await screen(
    'store-upgrades',
    () => const StoreView(),
    after: () => tab('Upgrades'),
  );
  await screen('collections', () => const CollectionsView());
  if (only == null) {
    final model = _model(theme);
    final rewardAds = _PreviewAds();
    addTearDown(rewardAds.dispose);
    await tester.pumpWidget(
      _shell(
        key,
        model,
        rewardAds,
        billing,
        Builder(
          builder: (context) => Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [CompletionBonus(context.watch<AppModel>())],
            ),
          ),
        ),
      ),
    );
    await model.open(const PuzzleId.level(1));
    complete(model);
    await tester.pump();
    await tester.pumpWidget(
      _shell(key, model, rewardAds, billing, const PuzzleView()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _snap(tester, key, '$label-level-completion');
    await tester.pump(const Duration(milliseconds: 875));
    await tester.ensureVisible(find.text('Stop'));
    expect(tester.takeException(), isNull);
    await _snap(tester, key, '$label-multiplier-moving');
    await tester.ensureVisible(find.text('Stop'));
    await tester.tap(find.text('Stop'));
    await shot('multiplier-stopped');
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
    final discoveryModel = _model(theme, discoveryClears: 9);
    await tester.pumpWidget(
      _shell(key, discoveryModel, rewardAds, billing, const PuzzleView()),
    );
    await discoveryModel.open(const PuzzleId.level(1));
    complete(discoveryModel);
    await shot('discovery-reveal');
    await tester.pumpWidget(
      _shell(key, discoveryModel, rewardAds, billing, const CollectionsView()),
    );
    await shot('pending-discovery');
    await tester.pumpWidget(const SizedBox.shrink());
    await discoveryModel.flush();
    discoveryModel.dispose();
    final crateModel = _model(theme);
    await tester.pumpWidget(
      _shell(key, crateModel, rewardAds, billing, const PuzzleView()),
    );
    await crateModel.open(const PuzzleId.level(1));
    crateModel.forceCrateForDebug();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Catch supply crate'));
    await shot('supply-crate');
    await tester.pumpWidget(const SizedBox.shrink());
    await crateModel.flush();
    crateModel.dispose();
  }
  await screen('journey', () => const LevelsView());
  await screen('levels', () => const LevelsView(quickNavigation: true));
  if (only == null) {
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {
        'preferences': {'theme': theme.name},
        'ownedThemes': [theme.name],
        'journey': {
          'chapterChests': [0],
        },
        'results': {
          for (var level = 1; level <= 25; level++)
            'levels/$level': {'milliseconds': 57000, 'hints': 0},
        },
      },
    );
    await tester.pumpWidget(
      _shell(key, model, ads, billing, const LevelsView()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Treasures · 1'));
    await tester.pumpAndSettle();
    final treasure = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('First Light'),
    );
    await tester.tap(treasure);
    await shot('chapter-treasure');
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  }
  await screen('research', () => const ProgressionView());
  await screen('boosts', () => const ProgressionView(boosts: true));
  await screen(
    'wheel',
    () => const FortuneView(),
    after: () async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    },
  );
  await screen('streak', () => const StreakView());
  await screen('stats', () => const StatisticsView());
  await screen(
    'achievements',
    () => const StatisticsView(),
    after: () async {
      await tester.scrollUntilVisible(find.text('Pathwise Achievements'), 220);
    },
  );
  await screen('settings', () => const SettingsView());
  await screen(
    'tutorial',
    () => MechanicTutorialView(
      mechanic: MechanicTutorial.walls,
      onAcknowledge: (_) async => true,
    ),
  );
  await screen(
    'connection',
    () => ConnectionPane(
      state: ConnectivityState.offline,
      palette: BoardPalette.palettes[theme]!,
      inPlay: true,
      onRetry: () async {},
    ),
  );
  await screen(
    'theme-preview',
    () => const StoreView(),
    after: () async {
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('theme-card-field')),
          matching: find.byType(LevelOneBoardPreview),
        ),
      );
      await tester.pumpAndSettle();
    },
  );
  await screen(
    'tip-preview',
    () => const StoreView(),
    after: () async {
      await tab('Tips');
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('tip-card-arrow')),
          matching: find.byType(TipArtwork),
        ),
      );
      await tester.pumpAndSettle();
    },
  );
  await screen(
    'insufficient',
    () => Builder(
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => showInsufficientCoins(
            context,
            itemName: 'Forest Mint',
            requiredCoins: 90,
            currentBalance: 50,
          ),
        );
        return const Scaffold();
      },
    ),
  );
}

void main() {
  setUpAll(() async {
    final font = File('assets/fonts/BricolageGrotesque.ttf');
    if (font.existsSync()) {
      final loader = FontLoader('Bricolage')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    // Icons render as boxes unless the Material icon font is loaded.
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final icons = File(
        '${dir.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        final loader = FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
        await loader.load();
        break;
      }
      if (dir.path == dir.parent.path) break;
    }
  });

  for (final MapEntry(key: label, value: theme) in _themes.entries) {
    testWidgets('every screen renders cleanly on the $label theme', (
      tester,
    ) async {
      await _screens(
        tester,
        theme: theme,
        label: label,
        size: const Size(390, 844),
      );
    });
  }

  for (final (name, size, scale) in [
    ('small', const Size(360, 640), 1.0),
    ('large', const Size(430, 932), 1.0),
    ('text', const Size(360, 640), 1.5),
    ('tiny', const Size(320, 568), 1.0),
    ('tablet', const Size(800, 1000), 1.0),
  ]) {
    testWidgets('key screens fit the $name viewport', (tester) async {
      await _screens(
        tester,
        theme: PathwiseTheme.field,
        label: 'field-$name',
        size: size,
        textScale: scale,
        only: {
          'home',
          'puzzle',
          'store-themes',
          'store-tips',
          'store-coins',
          'store-upgrades',
          'research',
          'wheel',
        },
      );
    });
  }

  testWidgets('every tip renders on every theme and forms a contact sheet', (
    tester,
  ) async {
    expect(PathTip.values.length, 20);
    await tester.binding.setSurfaceSize(const Size(760, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final MapEntry(key: label, value: theme) in _themes.entries) {
      final palette = BoardPalette.palettes[theme]!;
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: palette.canvas,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final tip in PathTip.values)
                      SizedBox(
                        width: 130,
                        child: Column(
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              color: palette.surface,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 46,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      color: palette.route,
                                      borderRadius: BorderRadius.circular(23),
                                    ),
                                  ),
                                  TipArtwork(
                                    tip: tip,
                                    palette: palette,
                                    scale: .45,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              tip.label,
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 12,
                                fontFamily: 'Bricolage',
                                decoration: TextDecoration.none,
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
      await tester.pump();
      expect(tester.takeException(), isNull, reason: label);
      await _snap(tester, key, 'tips-$label');
    }
  });
  testWidgets('the production artwork renders labeled inventory sheets', (
    tester,
  ) async {
    final field = BoardPalette.palettes[PathwiseTheme.field]!;
    Future<void> sheet(
      String name,
      List<(String, Widget)> entries, {
      BoardPalette? colors,
      int columns = 5,
      double width = 150,
      double height = 86,
    }) async {
      final palette = colors ?? field;
      final key = GlobalKey();
      final rows = (entries.length / columns).ceil();
      await tester.binding.setSurfaceSize(
        Size(columns * width + 32, rows * (height + 39) + 32),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: palette.theme,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.count(
                  crossAxisCount: columns,
                  mainAxisExtent: height + 39,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final (label, art) in entries)
                      Column(
                        children: [
                          SizedBox(
                            height: height,
                            child: Center(child: art),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: const TextStyle(fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      await _snap(tester, key, name);
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
    await sheet('controls', [
      for (final glyph in ControlGlyph.values)
        (glyph.name, PathIcon(glyph, size: 24)),
    ]);
    await sheet('resources', [
      for (final kind in [
        ...ArtKind.values.take(18),
        ArtKind.treasure,
        ArtKind.treasureOpen,
      ])
        (kind.name, GameArt(kind, palette: field, size: 58)),
    ]);
    await sheet('research-art', [
      for (final item in Research.values)
        (item.title, ResearchArtwork(item, palette: field)),
    ]);
    await sheet('boost-art', [
      for (final boost in Boost.values)
        (
          '${boost.multiplier}× · ${boost.minutes} min',
          BoostArtwork(boost, palette: field, size: 62),
        ),
    ], columns: 4);
    await sheet('achievement-emblems', [
      for (final achievement in Achievement.values)
        (
          achievement.title,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AchievementEmblem(
                achievement,
                palette: field,
                earned: true,
                size: 53,
              ),
              AchievementEmblem(
                achievement,
                palette: field,
                earned: false,
                size: 43,
              ),
            ],
          ),
        ),
    ]);
    await sheet(
      'chapter-illustrations',
      [
        for (var chapter = 0; chapter < 8; chapter++)
          (
            chapterName(chapter),
            JourneyArt(field, chapter: chapter, height: 100),
          ),
      ],
      columns: 2,
      width: 340,
      height: 110,
    );
    await sheet('mystery-silhouettes', [
      for (final (index, tip) in PathTip.values.skip(1).indexed)
        (
          'Unknown ${index + 1}',
          SizedBox.square(
            dimension: 62,
            child: TipArtwork(tip: tip, palette: field, concealed: true),
          ),
        ),
    ]);
    await sheet(
      'reward-illustrations',
      [
        for (final kind in [
          ArtKind.coinStack3,
          ArtKind.gift,
          ArtKind.crate,
          ArtKind.crown,
        ])
          (kind.name, GameArt(kind, palette: field, size: 96)),
      ],
      columns: 4,
      height: 106,
    );
    for (final theme in [
      PathwiseTheme.field,
      PathwiseTheme.blackwater,
      PathwiseTheme.signal,
    ]) {
      final palette = BoardPalette.palettes[theme]!;
      final model = _model(theme);
      await model.open(const PuzzleId.level(1));
      model.begin(0);
      for (final (step, pose) in [
        (1, 'horizontal'),
        (2, 'checkpoint'),
        (5, 'corner-vertical'),
      ]) {
        model.step(step);
        await sheet(
          'board-${theme.name}-$pose',
          [
            for (final tip in PathTip.values)
              (
                tip.label,
                SizedBox.square(
                  dimension: 216,
                  child: PuzzleBoard(
                    model: model,
                    puzzle: fixture().puzzle,
                    palette: palette,
                    tipStyle: tip,
                  ),
                ),
              ),
          ],
          colors: palette,
          columns: 5,
          width: 224,
          height: 216,
        );
      }
      model.end();
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
    }
  });
}
