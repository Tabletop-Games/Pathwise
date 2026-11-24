import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/main.dart';
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/path_tips.dart';
import '../lib/model/user_preferences.dart';
import '../lib/views/components/economy_navigation.dart';
import '../lib/views/components/tip_art.dart';
import '../lib/views/fortune_view.dart';
import '../lib/views/levels_view.dart';
import '../lib/views/progression_view.dart';
import '../lib/views/settings_view.dart';
import '../lib/views/store_view.dart';
import '../lib/views/streak_view.dart';
import 'app_model_test.dart' show MemoryStorage, fixture;

/// Renders every screen on the six reference themes and checks that nothing
/// overflows or throws. When `PATHWISE_CAPTURE_DIR` is set it also writes a
/// PNG per screen and a contact sheet of every path tip, so the output can be
/// inspected.
final _captureDir = Platform.environment['PATHWISE_CAPTURE_DIR'];

const _themes = <String, PathwiseTheme>{
  'light': PathwiseTheme.field,
  'dark': PathwiseTheme.blackwater,
  'warm': PathwiseTheme.warmWalnut,
  'cool': PathwiseTheme.glacier,
  'amoled': PathwiseTheme.amoledCarbon,
  'contrast': PathwiseTheme.signal,
};

AppModel _model(PathwiseTheme theme) => AppModel(
  storage: MemoryStorage(),
  snapshot: {
    'preferences': {'theme': theme.name},
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
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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
    await tester.pumpAndSettle();
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
  await screen('levels', () => const LevelsView());
  await screen('research', () => const ProgressionView());
  await screen('boosts', () => const ProgressionView(boosts: true));
  await screen('wheel', () => const FortuneView());
  await screen('streak', () => const StreakView());
  await screen('stats', () => const StatisticsView());
  await screen('settings', () => const SettingsView());
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
                                    scale: .6,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              tip.label,
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 12,
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
}
