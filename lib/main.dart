import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'logic/achievement_sync.dart';
import 'logic/ad_service.dart';
import 'logic/attack_clock.dart';
import 'logic/billing_service.dart';
import 'logic/game_state_storage.dart';
import 'model/app_model.dart';
import 'model/app_themes.dart';
import 'model/user_preferences.dart';
import 'views/main_menu_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Pathwise',
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Bricolage Grotesque',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final storage = GameStateStorage();
  final clock = AttackClock();
  Map<String, dynamic>? snapshot;
  try {
    snapshot = await storage.load();
  } catch (_) {
    storage.protect();
  }
  final prefs = snapshot?['preferences'];
  final theme = prefs is Map<String, dynamic>
      ? UserPreferences.fromJson(prefs).theme
      : PathwiseTheme.field;
  runApp(
    PathwiseStartup(
      theme: theme,
      clock: clock,
      initialize: () async {
        await clock.sync();
        try {
          if (snapshot == null) throw StateError('Save could not be loaded');
          final model = AppModel(
            storage: storage,
            snapshot: snapshot,
            bootTime: clock.read,
            debugTools: kDebugMode,
          );
          if (snapshot.isNotEmpty &&
              snapshot['schemaVersion'] != GameStateStorage.schemaVersion) {
            await model.flush();
          }
          return model;
        } catch (_) {
          storage.protect();
          return AppModel(storage: storage, snapshot: {}, bootTime: clock.read)
            ..storageError = true;
        }
      },
    ),
  );
}

class PathwiseStartup extends StatefulWidget {
  const PathwiseStartup({
    required this.theme,
    required this.initialize,
    this.clock,
    super.key,
  });

  final PathwiseTheme theme;
  final Future<AppModel> Function() initialize;
  final AttackClock? clock;

  @override
  State<PathwiseStartup> createState() => _PathwiseStartupState();
}

class _PathwiseStartupState extends State<PathwiseStartup> {
  late final Future<AppModel> _startup;

  @override
  void initState() {
    super.initState();
    _startup = WidgetsBinding.instance.endOfFrame.then(
      (_) => widget.initialize(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppModel>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.data case final model?) {
          return ChangeNotifierProvider(
            create: (_) => model,
            child: PathwiseApp(clock: widget.clock, offerLevelOneDemo: true),
          );
        }
        final palette = BoardPalette.palettes[widget.theme]!;
        return MaterialApp(
          title: 'Pathwise',
          debugShowCheckedModeBanner: false,
          theme: palette.theme,
          home: Scaffold(
            key: const ValueKey('pathwise-splash'),
            backgroundColor: palette.canvas,
            body: Center(
              child: Text(
                'Pathwise',
                style: palette.theme.textTheme.headlineMedium?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PathwiseApp extends StatefulWidget {
  const PathwiseApp({this.clock, this.offerLevelOneDemo = false, super.key});
  final bool offerLevelOneDemo;
  final AttackClock? clock;

  @override
  State<PathwiseApp> createState() => _PathwiseAppState();
}

class _PathwiseAppState extends State<PathwiseApp> with WidgetsBindingObserver {
  Timer? _dayCheck;
  late final AppModel _model;
  late final BillingService _billing;
  late final AdService _ads;
  late final AchievementSync _achievements;
  String? _lastDay;

  @override
  void initState() {
    super.initState();
    _model = context.read<AppModel>();
    _achievements = AchievementSync(_model);
    _ads = AdService(
      reserveInterstitial: _model.reserveAutomaticAd,
      onRewardedClosed: _model.recordRewardedAdExit,
    );
    _billing = BillingService(
      persist: (grant) => _model.applyVerifiedPurchase(
        grant.id,
        coins: storeProducts[grant.product]!.coins,
        themes: grant.product == themePassProduct,
        removeAds: grant.product == removeAdsProduct,
        bundle: grant.product == premiumProduct,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _model.refreshAttackClock();
        _achievements.foreground(true);
        unawaited(_billing.start());
      }
    });
    WidgetsBinding.instance.addObserver(this);
    _watchDate();
  }

  void _watchDate() {
    _dayCheck?.cancel();
    _checkDay();
    _dayCheck = Timer.periodic(const Duration(seconds: 15), (_) => _checkDay());
  }

  void _checkDay() {
    final day = _model.daily.key;
    if (_lastDay != null && _lastDay != day) _model.refreshDate();
    _lastDay = day;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _achievements.foreground(active);
    if (active) {
      _watchDate();
      unawaited(_refreshAttackClock());
    } else {
      _model.setForeground(false);
      _dayCheck?.cancel();
    }
  }

  Future<void> _refreshAttackClock() async {
    await widget.clock?.sync();
    if (mounted &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _model.refreshAttackClock();
      _model.setForeground(true);
    }
  }

  @override
  void dispose() {
    _dayCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _billing.dispose();
    _ads.dispose();
    _achievements.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.select((AppModel model) => model.theme);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _billing),
        ChangeNotifierProvider.value(value: _ads),
        ChangeNotifierProvider.value(value: _achievements),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pathwise',
        theme: BoardPalette.palettes[theme]!.theme,
        home: MainMenuView(
          offerDailySpin: widget.clock != null,
          offerLevelOneDemo: widget.offerLevelOneDemo,
        ),
      ),
    );
  }
}
