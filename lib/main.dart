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
import 'logic/play_games.dart';
import 'model/app_model.dart';
import 'model/app_themes.dart';
import 'model/user_preferences.dart';
import 'online/api_client.dart';
import 'online/identity_store.dart';
import 'online/online_service.dart';
import 'views/components/brand_mark.dart';
import 'views/connection_view.dart';
import 'views/main_menu_view.dart';

/// Build-time configuration. The environment follows the build mode and
/// cannot be overridden: debug and profile builds (`.debug` app ID) only talk
/// to a development backend, release builds only to production. The service
/// refuses a backend that reports the other environment.
const _apiBase = String.fromEnvironment('PATHWISE_API_BASE');
const _build = int.fromEnvironment('PATHWISE_BUILD');
const _environment = kReleaseMode ? 'production' : 'development';
const _gamesWebClient = String.fromEnvironment('PATHWISE_PGS_WEB_CLIENT_ID');

OnlineService createOnlineService([HttpTransport? transport]) {
  final http = transport ?? IoTransport();
  return OnlineService(
    api: ApiClient(baseUrl: _apiBase, transport: http, build: _build),
    store: IdentityStore(),
    packageName: _environment == 'production'
        ? 'com.shenmareparas.pathwise'
        : 'com.shenmareparas.pathwise.debug',
    expectedEnv: _environment,
    timezoneMinutes: () => DateTime.now().timeZoneOffset.inMinutes,
    internetProbe: () async {
      final response = await http.send(
        'GET',
        Uri.parse('https://www.gstatic.com/generate_204'),
        headers: const {},
        timeout: const Duration(seconds: 4),
      );
      return response.status == 204 || response.ok;
    },
    gamesCode: PlayGames.enabled && _gamesWebClient.isNotEmpty
        ? () async {
            if (await PlayGames.call<bool>('status') != true &&
                await PlayGames.call<bool>('signIn') != true) {
              return null;
            }
            return PlayGames.call<String>('serverAuthCode', {
              'clientId': _gamesWebClient,
            });
          }
        : null,
  );
}

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
  final online = createOnlineService();
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
      final model = AppModel(
        storage: storage,
        snapshot: snapshot,
        bootTime: clock.read,
        debugTools: kDebugMode,
        online: online,
      );
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
        online: online,
      )..storageError = true;
    }
  }

  /// The local save is only a cache. The server's state replaces it as soon as
  /// a session exists. The native splash is held for at most three seconds;
  /// after that the themed connecting screen takes over while this continues.
  Future<AppModel> connect() async {
    final model = await initialize();
    online
      ..onState = model.applyServerState
      ..onWallet = model.applyWallet
      ..onRejected = (command, response) => unawaited(model.resync());
    await online.start().timeout(const Duration(seconds: 3), onTimeout: () {});
    return model;
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final model = await connect();
    runApp(
      ChangeNotifierProvider(
        create: (_) => model,
        child: PathwiseApp(
          clock: clock,
          offerLevelOneDemo: true,
          online: online,
        ),
      ),
    );
  } else {
    runApp(
      PathwiseStartup(
        theme: theme,
        clock: clock,
        initialize: connect,
        online: online,
      ),
    );
  }
}

class PathwiseStartup extends StatefulWidget {
  const PathwiseStartup({
    required this.theme,
    required this.initialize,
    this.clock,
    this.online,
    super.key,
  });

  final PathwiseTheme theme;
  final Future<AppModel> Function() initialize;
  final AttackClock? clock;
  final OnlineService? online;

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
              ? ChangeNotifierProvider(
                  key: const ValueKey('pathwise-app'),
                  create: (_) => model,
                  child: PathwiseApp(
                    clock: widget.clock,
                    offerLevelOneDemo: true,
                    online: widget.online,
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
    this.online,
    super.key,
  });
  final bool offerLevelOneDemo;
  final AttackClock? clock;

  /// Absent only in widget tests. Production always supplies it, which
  /// enables the connection gate and server-verified rewards and purchases.
  final OnlineService? online;

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
    final online = widget.online;
    _ads = AdService(
      reserveInterstitial: _model.reserveAutomaticAd,
      onRewardedClosed: _model.recordRewardedAdExit,
      startRewardSession: online == null
          ? null
          : (placement, kind) => online.startReward(placement.name, kind: kind),
      isConnected: online == null ? null : () => online.canPlay,
    );
    _billing = BillingService(
      gateway: online,
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
    widget.online?.setForeground(active);
    if (active && widget.online?.canPlay == false) {
      unawaited(widget.online!.retryNow());
    }
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
        if (widget.online != null)
          ChangeNotifierProvider<OnlineService>.value(value: widget.online!),
        ChangeNotifierProvider.value(value: _billing),
        ChangeNotifierProvider.value(value: _ads),
        ChangeNotifierProvider.value(value: _achievements),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pathwise',
        theme: BoardPalette.palettes[theme]!.theme,
        builder: widget.online == null
            ? null
            : (context, child) => ConnectionGate(child: child),
        home: MainMenuView(
          offerDailySpin: widget.clock != null,
          offerLevelOneDemo: widget.offerLevelOneDemo,
        ),
      ),
    );
  }
}
