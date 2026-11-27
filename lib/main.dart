import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'cloud/cloud_save_provider.dart';
import 'cloud/cloud_sync_service.dart';
import 'cloud/key_value_store.dart';
import 'logic/achievement_sync.dart';
import 'logic/ad_service.dart';
import 'logic/attack_clock.dart';
import 'logic/billing_service.dart';
import 'logic/connectivity_service.dart';
import 'logic/game_state_storage.dart';
import 'logic/play_games.dart';
import 'model/app_model.dart';
import 'model/app_themes.dart';
import 'model/user_preferences.dart';
import 'ui/art/game_assets.dart';
import 'views/cloud_save_section.dart';
import 'views/components/brand_mark.dart';
import 'views/connection_view.dart';
import 'views/main_menu_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 200;
  unawaited(GameAssetCache.instance.preloadAll());
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
  final connectivity = ConnectivityService(probe: () => probeInternet());
  final keyValues = PreferencesKeyValueStore();
  final session = AppSession();
  session.cloud = CloudSyncService(
    provider: cloudProviderFor(keyValues),
    store: keyValues,
    prefix: kDebugMode ? 'pathwise.debug.cloud' : 'pathwise.cloud',
    providerName: kDebugMode && !PlayGames.enabled
        ? 'a local test save'
        : 'Google Play Games',
    snapshot: () => session.model.snapshotMap(),
    apply: session.replaceModel,
    isOnline: () => connectivity.online,
  );
  session.connectivity = connectivity;
  session.buildModel = (snapshot) => AppModel(
    storage: storage,
    snapshot: snapshot,
    bootTime: clock.read,
    debugTools: kDebugMode,
    connectivity: connectivity,
    onPersisted: session.cloud.localChanged,
  );

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
  Future<AppModel> initialize() async {
    await clock.sync();
    try {
      if (snapshot == null) throw StateError('Save could not be loaded');
      final model = session.buildModel(snapshot);
      if (snapshot.isNotEmpty &&
          snapshot['schemaVersion'] != GameStateStorage.schemaVersion) {
        await model.flush();
      }
      return model;
    } catch (_) {
      storage.protect();
      return AppModel(
        storage: storage,
        snapshot: {},
        bootTime: clock.read,
        connectivity: connectivity,
      )..storageError = true;
    }
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    session.attach(await initialize());
    runApp(PathwiseRoot(session: session, clock: clock));
  } else {
    runApp(
      PathwiseStartup(
        theme: theme,
        clock: clock,
        initialize: () async {
          session.attach(await initialize());
          return session.model;
        },
        session: session,
      ),
    );
  }
}

/// Chooses the save provider. Release builds without Play Games configuration
/// run with sync off. Debug builds without it use a local fake, so the debug
/// package never reaches a production Play Games project.
CloudSaveProvider cloudProviderFor(KeyValueStore store) {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return const UnsupportedCloudSaves();
  }
  if (PlayGames.enabled) return PlayGamesCloudSaves(enabled: PlayGames.enabled);
  if (kReleaseMode) return const UnsupportedCloudSaves();
  return FakeCloudSaves(store: store, key: 'pathwise.debug.fakecloud.v1');
}

/// Owns the current [AppModel] and the services that outlive it. A cloud
/// restore builds a new model and the UI rebuilds around it.
class AppSession extends ChangeNotifier {
  AppModel? _model;
  int generation = 0;
  late ConnectivityService connectivity;
  late CloudSyncService cloud;
  late AppModel Function(Map<String, dynamic> snapshot) buildModel;

  AppModel get model => _model!;

  void attach(AppModel model) {
    _model = model;
  }

  /// Replaces the device save with [payload] and rebuilds the app on it.
  Future<bool> replaceModel(Map<String, dynamic> payload) async {
    final old = _model;
    final next = buildModel(payload);
    final saved = await next.flush();
    if (!saved) {
      next.dispose();
      return false;
    }
    _model = next;
    generation++;
    notifyListeners();
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    return true;
  }
}

/// Root of the running app once the save has loaded. Starts connectivity and
/// cloud sync, and reacts to lifecycle changes.
class PathwiseRoot extends StatefulWidget {
  const PathwiseRoot({required this.session, this.clock, super.key});

  final AppSession session;
  final AttackClock? clock;

  @override
  State<PathwiseRoot> createState() => _PathwiseRootState();
}

class _PathwiseRootState extends State<PathwiseRoot>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.connectivity.addListener(_connectivityChanged);
    widget.session.addListener(_sessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.session.connectivity.start());
      unawaited(widget.session.cloud.start());
    });
  }

  void _connectivityChanged() {
    if (widget.session.connectivity.online) {
      widget.session.cloud.scheduleSync(urgent: true);
    }
  }

  void _sessionChanged() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    widget.session.connectivity.setForeground(active);
    if (!active) {
      // Push pending progress out before the process can be suspended.
      unawaited(widget.session.cloud.syncNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.connectivity.removeListener(_connectivityChanged);
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ChangeNotifierProvider<AppModel>.value(
      key: ValueKey('pathwise-model-${session.generation}'),
      value: session.model,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<ConnectivityService>.value(
            value: session.connectivity,
          ),
          ChangeNotifierProvider<CloudSyncService>.value(value: session.cloud),
        ],
        child: PathwiseApp(
          key: ValueKey('pathwise-app-${session.generation}'),
          clock: widget.clock,
          offerLevelOneDemo: true,
          connectivity: session.connectivity,
        ),
      ),
    );
  }
}

class PathwiseStartup extends StatefulWidget {
  const PathwiseStartup({
    required this.theme,
    required this.initialize,
    this.clock,
    this.session,
    super.key,
  });

  final PathwiseTheme theme;
  final Future<AppModel> Function() initialize;
  final AttackClock? clock;

  /// Present in the running app. Absent in widget tests, which only check the
  /// startup transition.
  final AppSession? session;

  @override
  State<PathwiseStartup> createState() => _PathwiseStartupState();
}

class _PathwiseStartupState extends State<PathwiseStartup> {
  late final Future<AppModel> _startup;

  @override
  void initState() {
    super.initState();
    _startup = WidgetsBinding.instance.endOfFrame.then((_) async {
      final values = await Future.wait([
        widget.initialize(),
        Future<void>.delayed(const Duration(milliseconds: 700)),
      ]);
      return values.first as AppModel;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppModel>(
      future: _startup,
      builder: (context, snapshot) {
        final palette = BoardPalette.palettes[widget.theme]!;
        final model = snapshot.data;
        return AnimatedSwitcher(
          duration: MediaQuery.maybeDisableAnimationsOf(context) == true
              ? Duration.zero
              : const Duration(milliseconds: 450),
          child: model != null
              ? widget.session != null
                    ? PathwiseRoot(
                        key: const ValueKey('pathwise-app'),
                        session: widget.session!,
                        clock: widget.clock,
                      )
                    : ChangeNotifierProvider(
                        key: const ValueKey('pathwise-app'),
                        create: (_) => model,
                        child: PathwiseApp(
                          clock: widget.clock,
                          offerLevelOneDemo: true,
                        ),
                      )
              : MaterialApp(
                  key: const ValueKey('pathwise-loading'),
                  title: 'Pathwise',
                  debugShowCheckedModeBanner: false,
                  theme: palette.theme,
                  home: Scaffold(
                    key: const ValueKey('pathwise-splash'),
                    backgroundColor: palette.canvas,
                    body: Center(
                      child: SizedBox.square(
                        dimension: 80,
                        child: BrandMark(
                          background: palette.route,
                          ink: palette.onRoute,
                        ),
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
  const PathwiseApp({
    this.clock,
    this.offerLevelOneDemo = false,
    this.connectivity,
    super.key,
  });
  final bool offerLevelOneDemo;
  final AttackClock? clock;

  /// Absent in widget tests. Production always supplies it, which enables the
  /// internet requirement.
  final ConnectivityService? connectivity;

  @override
  State<PathwiseApp> createState() => _PathwiseAppState();
}

class _PathwiseAppState extends State<PathwiseApp> with WidgetsBindingObserver {
  Timer? _dayCheck;
  late final AppModel _model;
  late final BillingService _billing;
  late final AdService _ads;
  late final AchievementSync _achievements;
  final _navigator = GlobalKey<NavigatorState>();
  String? _lastDay;

  @override
  void initState() {
    super.initState();
    _model = context.read<AppModel>();
    final connectivity = widget.connectivity;
    _achievements = AchievementSync(
      _model,
      isConnected: connectivity == null ? null : () => connectivity.online,
    );
    _ads = AdService(
      reserveInterstitial: _model.reserveAutomaticAd,
      onRewardedClosed: _model.recordRewardedAdExit,
      onAdPlayingChanged: _model.setAdPlaying,
      isConnected: connectivity == null ? null : () => connectivity.online,
    );
    unawaited(_model.sound.preload());
    final cloud = context.read<CloudSyncService?>();
    _billing = BillingService(
      canPurchase: connectivity == null ? null : () => connectivity.online,
      persist: (grant) => _model.applyVerifiedPurchase(
        grant.id,
        coins: storeProducts[grant.product]!.coins,
        themes: grant.product == themePassProduct,
        removeAds: grant.product == removeAdsProduct,
        bundle: grant.product == premiumProduct,
      ),
      readyForConsumable: cloud == null
          ? null
          : () => cloud.prepareForPurchase(),
      beforeConsume: cloud == null
          ? null
          : () async {
              await cloud.syncNow();
            },
      onOwnedProducts: _model.reconcileOwnedProducts,
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
    final connectivity = widget.connectivity;
    final cloud = context.read<CloudSyncService?>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _billing),
        ChangeNotifierProvider.value(value: _ads),
        ChangeNotifierProvider.value(value: _achievements),
      ],
      child: MaterialApp(
        navigatorKey: _navigator,
        debugShowCheckedModeBanner: false,
        title: 'Pathwise',
        theme: BoardPalette.palettes[theme]!.theme,
        builder: connectivity == null
            ? null
            : (context, child) => CloudChoiceWatcher(
                navigatorKey: _navigator,
                cloud: cloud,
                child: ConnectionGate(connectivity: connectivity, child: child),
              ),
        home: MainMenuView(
          offerDailySpin: widget.clock != null,
          offerLevelOneDemo: widget.offerLevelOneDemo,
        ),
      ),
    );
  }
}
