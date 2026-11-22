import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'logic/game_state_storage.dart';
import 'model/app_model.dart';
import 'model/app_themes.dart';
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
  Map<String, dynamic> snapshot = {};
  var loadFailed = false;
  try {
    snapshot = await storage.load();
  } catch (_) {
    loadFailed = true;
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) =>
          AppModel(storage: storage, snapshot: snapshot)
            ..storageError = loadFailed,
      child: const PathwiseApp(),
    ),
  );
}

class PathwiseApp extends StatefulWidget {
  const PathwiseApp({super.key});

  @override
  State<PathwiseApp> createState() => _PathwiseAppState();
}

class _PathwiseAppState extends State<PathwiseApp> with WidgetsBindingObserver {
  Timer? _dayCheck;
  late final AppModel _model;
  String? _lastDay;

  @override
  void initState() {
    super.initState();
    _model = context.read<AppModel>();
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
    _model.setForeground(active);
    if (active) {
      _watchDate();
    } else {
      _dayCheck?.cancel();
    }
  }

  @override
  void dispose() {
    _dayCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.select((AppModel model) => model.theme);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pathwise',
      theme: BoardPalette.palettes[theme]!.theme,
      home: const MainMenuView(),
    );
  }
}
